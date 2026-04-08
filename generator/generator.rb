require 'docker'
require 'yaml'
require 'fileutils'

STDOUT.sync = true

# Traefik's dynamic configuration file path
CONFIG_PATH = ENV.fetch('DYNAMIC_CONFIG_PATH', '/config/dynamic_conf.yml')

def generate_config
  puts "Scanning containers..."
  begin
    containers = Docker::Container.all
    puts "Found #{containers.size} containers."
  rescue => e
    warn "Error fetching containers: #{e.message}"
    return
  end

  http_routers = {}
  http_services = {}

  containers.each do |container|
    info = container.json
    container_name = info['Name'].sub(%r{^/}, '') # remove leading slash
    
    # Select the IP address from 'traefik-net' if it exists, otherwise use the first network
    networks = info['NetworkSettings']['Networks']
    network = networks['traefik-net'] || networks.values.first
    ip_address = network&.[]('IPAddress')
    
    next if ip_address.nil? || ip_address.empty?

    # Find exposed ports
    exposed_ports = (info['Config']['ExposedPorts'] || {}).keys.map { |p| p.split('/').first }
    network_ports = (info['NetworkSettings']['Ports'] || {}).keys.map { |p| p.split('/').first }
    
    all_ports = (exposed_ports + network_ports).uniq

    all_ports.each do |port|
      service_id = "#{container_name}-#{port}"
      router_id = "#{service_id}-router"
      
      # http://<container-name>-<port>.localhost/
      rule = "Host(`#{container_name}-#{port}.localhost`)"
      url = "http://#{ip_address}:#{port}"

      http_routers[router_id] = {
        'rule' => rule,
        'service' => service_id
      }
      
      http_services[service_id] = {
        'loadBalancer' => {
          'servers' => [{ 'url' => url }]
        }
      }
    end
  end

  # Add router for the dashboard at http://localhost/
  http_routers['dashboard-localhost'] = {
    'rule' => 'Host(`localhost`)',
    'service' => 'api@internal'
  }

  config = {
    'http' => {
      'routers' => http_routers,
      'services' => http_services
    }
  }

  # Ensure directory exists and write the config as YAML
  FileUtils.mkdir_p(File.dirname(CONFIG_PATH))
  File.write(CONFIG_PATH, YAML.dump(config))
  puts "Updated #{CONFIG_PATH} with #{http_routers.size} routers."
end

generate_config

puts "Starting Docker event listener..."
begin
  Docker::Event.stream do |event|
    if %w[start stop die destroy].include?(event.status)
      puts "Event detected: #{event.status} on #{event.from}"
      generate_config
    end
  end
rescue Docker::Error::TimeoutError
  retry
rescue => e
  warn "Error in event stream: #{e.message}"
  sleep 5
  retry
end
