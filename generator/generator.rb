require 'docker'
require 'yaml'
require 'fileutils'

# Traefik's dynamic configuration file path
CONFIG_PATH = ENV.fetch('DYNAMIC_CONFIG_PATH', '/config/dynamic_conf.yml')

def generate_config
  puts "Scanning containers..."
  containers = Docker::Container.all

  http_routers = {}
  http_services = {}

  containers.each do |container|
    # Get container details including network settings
    info = container.json
    container_name = info['Name'].sub(%r{^/}, '') # remove leading slash
    
    # Use the first available network's IP address
    # In a real environment, you might want to specify a network name (e.g., 'traefik-net')
    network_settings = info['NetworkSettings']
    ip_address = network_settings['Networks'].values.first&.[]('IPAddress')
    
    next if ip_address.nil? || ip_address.empty?

    # Find exposed ports from Config or NetworkSettings
    # We collect all ports that are defined in ExposedPorts or currently bound
    exposed_ports = (info['Config']['ExposedPorts'] || {}).keys.map { |p| p.split('/').first }
    # Also add ports that are actually mapped (in case they aren't explicitly EXPOSEd)
    network_ports = (network_settings['Ports'] || {}).keys.map { |p| p.split('/').first }
    
    all_ports = (exposed_ports + network_ports).uniq

    all_ports.each do |port|
      service_id = "#{container_name}-#{port}"
      router_id = "#{service_id}-router"
      
      # http://<container-name>-<port>.localhost/
      rule = "Host(`#{container_name}-#{port}.localhost`)"
      url = "http://#{ip_address}:#{port}"

      http_routers[router_id] = {
        rule:,
        service: service_id
      }
      
      http_services[service_id] = {
        loadBalancer: {
          servers: [{ url: }]
        }
      }
    end
  end

  config = {
    http: {
      routers: http_routers,
      services: http_services
    }
  }

  # Ensure directory exists and write the config
  FileUtils.mkdir_p(File.dirname(CONFIG_PATH))
  File.write(CONFIG_PATH, config.to_yaml)
  puts "Updated #{CONFIG_PATH} with #{http_routers.size} routers."
end

# Initial generation
generate_config

# Watch Docker events for changes
puts "Starting Docker event listener..."
begin
  Docker::Event.stream do |event|
    # Re-generate config on relevant container lifecycle events
    if %w[start stop die destroy].include?(event.status)
      puts "Event detected: #{event.status} on #{event.from}"
      generate_config
    end
  end
rescue Docker::Error::TimeoutError
  # The stream might timeout; retry
  retry
rescue => e
  warn "Error in event stream: #{e.message}"
  sleep 5
  retry
end
