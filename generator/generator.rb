require 'docker'
require 'yaml'
require 'fileutils'
require 'pathname'

STDOUT.sync = true

# Traefik's dynamic configuration file path
CONFIG_PATH = Pathname(ENV.fetch('DYNAMIC_CONFIG_PATH', '/config/dynamic_conf.yml'))
TRAEFIK_NAME = ENV.fetch('TRAEFIK_CONTAINER_NAME', 'traefik-proxy')

def generate_config
  puts "Scanning containers at #{Time.now}..."
  begin
    # Explicitly set all: true to get all containers
    containers = Docker::Container.all(all: true)
    traefik_container = Docker::Container.get(TRAEFIK_NAME)
    my_id = Docker::Container.get('hostname').id rescue nil
  rescue => e
    warn "Error initializing: #{e.message}. Retrying..."
    return
  end

  http_routers = {}
  http_services = {}

  containers.each do |container|
    begin
      info = container.json
      container_id = info['Id']
      container_name = info['Name'].sub(%r{^/}, '')
      
      next unless info['State']['Status'] == 'running'
      next if container_name == TRAEFIK_NAME || container_id == my_id
      
      # Connect Traefik to all networks of the container
      networks = info['NetworkSettings']['Networks']
      networks.each do |net_name, _|
        next if net_name == 'none' || net_name == 'host'
        
        traefik_info = Docker::Container.get(TRAEFIK_NAME).json
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
      
      next if ip_address.nil? || ip_address.empty?

      # Ports
      exposed_ports = (info['Config']['ExposedPorts'] || {}).keys.map { |p| p.split('/').first }
      bound_ports = (info['NetworkSettings']['Ports'] || {}).keys.map { |p| p.split('/').first }
      all_ports = (exposed_ports + bound_ports).uniq
      
      all_ports.each do |port|
        service_id = "#{container_name}-#{port}"
        router_id = "#{service_id}-router"
        rule = "Host(`#{container_name}-#{port}.localhost`)"
        url = "http://#{ip_address}:#{port}"

        http_routers[router_id] = { 'rule' => rule, 'service' => service_id }
        http_services[service_id] = { 'loadBalancer' => { 'servers' => [{ 'url' => url }] } }
      end
    rescue => e
      warn "  Error processing #{container.id[0..11]}: #{e.message}"
    end
  end

  http_routers['dashboard-localhost'] = { 'rule' => 'Host(`localhost`)', 'service' => 'api@internal' }
  config = { 'http' => { 'routers' => http_routers, 'services' => http_services } }

  CONFIG_PATH.parent.mkpath
  CONFIG_PATH.write(YAML.dump(config))
  puts "Updated #{CONFIG_PATH} with #{http_routers.size} routers."
end

# Event listener in a separate thread
Thread.new do
  puts "Starting Docker event listener thread..."
  begin
    Docker::Event.stream do |event|
      if %w[start stop die destroy create].include?(event.status)
        puts "Event: #{event.status} on #{event.from}"
        sleep 2
        generate_config
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
  generate_config
  sleep 15
end
