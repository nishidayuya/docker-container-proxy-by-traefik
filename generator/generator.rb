require 'docker'
require 'yaml'
require 'fileutils'
require 'pathname'

STDOUT.sync = true

# Traefik's dynamic configuration file path
CONFIG_PATH = Pathname(ENV.fetch('DYNAMIC_CONFIG_PATH', '/config/dynamic_conf.yml'))
ACTUAL_TRAEFIK_NAME = ENV.fetch('TRAEFIK_CONTAINER_NAME', 'traefik-proxy')
TRAEFIK_NAME = ACTUAL_TRAEFIK_NAME.gsub('_', '-')

# Serializes generate_config between the event listener thread and the
# main loop so that they never write the config file concurrently.
CONFIG_LOCK = Mutex.new
# Routes of a container are kept for this many seconds after the last
# successful scan of it, so that transient errors do not remove them.
EXPIRE_SEC = Integer(ENV.fetch('TRAEFIK_GENERATOR_EXPIRE_SEC', '300'))
# Container ID => { routers:, services:, succeeded_at: } of the last
# successful scan. Accessed only while holding CONFIG_LOCK.
LAST_SUCCEEDED_ENTRIES = {}

def generate_config
  puts "Scanning containers at #{Time.now}..."
  begin
    # Explicitly set all: true to get all containers
    containers = Docker::Container.all(all: true)
    traefik_container = Docker::Container.get(ACTUAL_TRAEFIK_NAME)
    my_id = Docker::Container.get('hostname').id rescue nil
  rescue => e
    warn "Error initializing: #{e.message}. Retrying..."
    return
  end

  http_routers = {}
  http_services = {}
  now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  alive_container_ids = []

  containers.each do |container|
    # Use the list result so that routes are kept even if container.json fails.
    alive_container_ids << container.id if container.info['State'] == 'running'
    begin
      info = container.json
      container_id = info['Id']
      container_name = info['Name'].sub(%r{^/}, '').gsub('_', '-')
      
      next unless info['State']['Status'] == 'running'
      next if container_name == TRAEFIK_NAME || container_id == my_id

      # Connect Traefik to all networks of the container
      networks = info['NetworkSettings']['Networks']
      networks.each do |net_name, _|
        next if net_name == 'none' || net_name == 'host'
        
        traefik_info = Docker::Container.get(ACTUAL_TRAEFIK_NAME).json
        unless traefik_info['NetworkSettings']['Networks'].key?(net_name)
          puts "  Connecting Traefik to network: #{net_name} (from #{container_name})"
          begin
            Docker::Network.get(net_name).connect(traefik_container.id)
          rescue => e
            warn "  Could not connect Traefik to #{net_name}: #{e.message}"
          end
        end
      end

      # Refresh info to get IPs
      info = container.json
      network = info['NetworkSettings']['Networks'].values.find { |n| n['IPAddress'] && !n['IPAddress'].empty? }
      ip_address = network&.[]('IPAddress')
      
      raise 'no IP address' if ip_address.nil? || ip_address.empty?

      # Ports
      exposed_ports = (info['Config']['ExposedPorts'] || {}).keys.map { |p| p.split('/').first }
      bound_ports = (info['NetworkSettings']['Ports'] || {}).keys.map { |p| p.split('/').first }
      all_ports = (exposed_ports + bound_ports).uniq
      
      routers = {}
      services = {}
      all_ports.each do |port|
        service_id = "#{container_name}-#{port}"
        router_id = "#{service_id}-router"
        rule = "Host(`#{container_name}-#{port}.localhost`)"
        url = "http://#{ip_address}:#{port}"

        routers[router_id] = { 'rule' => rule, 'service' => service_id }
        services[service_id] = { 'loadBalancer' => { 'servers' => [{ 'url' => url }] } }
      end
      LAST_SUCCEEDED_ENTRIES[container_id] = { routers:, services:, succeeded_at: now }
    rescue => e
      warn "  Error processing #{container.id[0..11]}: #{e.message}"
    end
  end

  # Forget containers that are no longer running and those that have kept
  # failing for EXPIRE_SEC seconds. Others reuse their last successful result.
  LAST_SUCCEEDED_ENTRIES.select! do |container_id, entry|
    next false unless alive_container_ids.include?(container_id)

    elapsed = now - entry[:succeeded_at]
    if elapsed >= EXPIRE_SEC
      warn "  Expired routes of #{container_id[0..11]}: kept failing for #{elapsed.round} seconds"
      next false
    end

    true
  end
  LAST_SUCCEEDED_ENTRIES.each_value do |entry|
    http_routers.merge!(entry[:routers])
    http_services.merge!(entry[:services])
  end

  http_routers['dashboard-localhost'] = { 'rule' => 'Host(`localhost`)', 'service' => 'api@internal' }
  config = { 'http' => { 'routers' => http_routers, 'services' => http_services } }

  unless write_config(config)
    puts "No changes in #{CONFIG_PATH}."
    return
  end

  puts "Updated #{CONFIG_PATH} with #{http_routers.size} routers."
end

# Write the config atomically so that Traefik never reads an empty or
# partially written file. The temporary file has a ".tmp" extension, which
# Traefik's file provider ignores.
def write_config(config)
  content = YAML.dump(config)
  return false if CONFIG_PATH.exist? && CONFIG_PATH.read == content

  CONFIG_PATH.parent.mkpath
  tmp_path = CONFIG_PATH.sub_ext("#{CONFIG_PATH.extname}.tmp")
  tmp_path.write(content)
  tmp_path.rename(CONFIG_PATH)
  true
end

# Event listener in a separate thread
Thread.new do
  puts "Starting Docker event listener thread..."
  begin
    Docker::Event.stream do |event|
      if %w[start stop die destroy create].include?(event.status)
        puts "Event: #{event.status} on #{event.from}"
        sleep 2
        CONFIG_LOCK.synchronize { generate_config }
      end
    end
  rescue => e
    warn "Event stream error: #{e.message}. Restarting thread..."
    sleep 5
    retry
  end
end

# Main loop: periodic scan
loop do
  CONFIG_LOCK.synchronize { generate_config }
  sleep 15
end
