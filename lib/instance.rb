class Instance
  attr_accessor :name, :role, :connection, :profile, :options
  attr_reader :aws_id, :aws_description, :status, :role_config, :profile_role_config

  NA_STATUS = 'n/a'

  def self.new_for_service(service, *args)
    klass = case service.to_sym
    when :ec2 : Instance::EC2
    when :rds : Instance::RDS
    when :elb : Instance::ELB
    else raise ArgumentError, "No such service: #{service}"
    end

    klass.new(*args)
  end

  def initialize(name, status, profile, role_config, profile_role_config, command_options)
    @name = name
    @status = status
    @profile = profile

    @role_config = role_config
    @profile_role_config = profile_role_config
    @command_options = command_options

    @aws_id = nil
    @aws_description = {}
  end

  def sync!
    description = @connection.description_for_name(name, @role_config.service)
    sync_from_description(description)
  end

  def sync_from_description(description)
    @aws_description = description || {}
    @aws_id = self.class.description_aws_id(@aws_description)
    @status = self.class.description_status(@aws_description) || NA_STATUS
  end

  def terminated?
    status == 'terminated'
  end

  def alive?
    @aws_id && !terminated?
  end

  def to_s
    "#{name}   #{status}    #{@aws_id}"
  end

  def inspect
    "<Instance #{to_s}>"
  end

  def role_name
    @role_config.name
  end

  def has_approximate_status?(status)
    if status == "n/a" or status == "terminated"
      !alive?
    else
      status == @status
    end
  end

  def method_missing(method_name, *args, &block)
    @profile_role_config[method_name] ||
    @role_config[method_name] ||
    @aws_description[method_name] ||
    @command_options[method_name]
  end

  def config(key, required=false)
    if required && @profile_role_config[key].nil? && @role_config[key].nil?
      raise ArgumentError.new("Missing required config: #{key}")
    end

    @profile_role_config[key] || @role_config[key]
  end

  def configurations
    @@configurations_cache ||= {}
    @@configurations_cache[self.role_name] ||= merge_configurations(profile_role_config.configurations, role_config.configurations)
  end

  def display_fields
    [:name, :status]
  end

  protected
  def merge_configurations(profile_configurations, role_configurations)
    profile_configurations ||= []
    role_configurations ||= []

    amended_role_configurations = role_configurations.map do |base_configuration|
      overriden_configuration = configuration_with_name(base_configuration.name, profile_configurations) || {}
      base_configuration.deep_merge(overriden_configuration)
    end

    new_profile_configurations = profile_configurations.select do |profile_configuration|
      # this configuration is not defined in the role
      configuration_with_name(profile_configuration.name, role_configurations).nil?
    end

    amended_role_configurations | new_profile_configurations
  end

  def configuration_with_name(name, configurations)
    configurations.find {|c| c.name == name}
  end
end

require 'lib/instance/ec2'
require 'lib/instance/rds'
require 'lib/instance/elb'




