require 'rubygems'
require 'AWS'
require './lib/models'

#Set the aws keys in your env.
ACCESS_KEY_ID = ENV["AWS_ACCESS_KEY_ID"]
SECRET_ACCESS_KEY = ENV["AWS_SECRET_ACCESS_KEY"] 


DEFAULT_WEB_AMI = "ami-98d014f1"
DEFAULT_APP_AMI = "ami-bd07c3d4"
DEFAULT_LOADGEN_AMI = "ami-cb03c7a2"

class LcAws
  attr_accessor :ec2, :rds
  
  def initialize(region = "us-east-1")
    ec2_server = "ec2.us-east-1.amazonaws.com" if region == "us-east-1"
    ec2_server = "ec2.us-west-1.amazonaws.com" if region == "us-west-1"
    rds_server = "rds.us-east-1.amazonaws.com" if region == "us-east-1"
    rds_server = "rds.us-west-1.amazonaws.com" if region == "us-west-1"
    
    @ec2 = AWS::EC2::Base.new(:access_key_id => ACCESS_KEY_ID, :secret_access_key => SECRET_ACCESS_KEY, :server => ec2_server)
    @rds = AWS::RDS::Base.new(:access_key_id => ACCESS_KEY_ID, :secret_access_key => SECRET_ACCESS_KEY, :server => rds_server)
  end

  #
  # instance definitions
  #
  def get_instances
    all_instances = Array.new
    instance_data = get_instance_blob
    if instance_data != nil
      items = instance_data["reservationSet"]["item"]
      items.each do |i|
        new_instance = nil
        instances = i["instancesSet"]["item"]
        instances.each do |instance|
          new_instance = Ec2Instance.new(instance)
          all_instances << new_instance

          groups = i["groupSet"]["item"]
          new_instance.group = groups[0]['groupId']
        end
      end   
    end
    all_instances 
  end
  
  def get_rds_instances
    all_instances = Array.new
    db_instances = @rds.describe_db_instances["DescribeDBInstancesResult"]["DBInstances"]["DBInstance"]
    if db_instances != nil
      db_instances.each do |db_data|
        new_instance = RdsInstance.new(db_data)
        all_instances << new_instance
      end
    end
    all_instances
  end
 
  def get_rds_instances_by_name(name_filter)
    all_instances = get_rds_instances
    filtered_instances = Array.new
    all_instances.each do |instance|
      # check if the name matches
      if !instance.name.nil? and instance.name.include?(name_filter) 
        filtered_instances << instance
      else  
        puts instance.name.to_s
      end
    end
    filtered_instances
  end

 
  def get_app_instances(instances = nil, state = nil)
    get_instances_by_name("app", instances, state)
  end

  def get_loadgen_instances(instances = nil, state = nil)
    get_instances_by_name("gen", instances, state)
  end

  def get_web_instances(instances = nil, state = nil)
    get_instances_by_name("web", instances, state)
  end

  def get_instances_by_name(name_filter, instances = nil, state = nil)
    all_instances = instances
    all_instances = get_instances if all_instances.nil?
    filtered_instances = Array.new
    all_instances.each do |instance|
      # check if the name matches AND the state matches the filter provided
      if instance.name.include?(name_filter) && (state.nil? || instance.state == state)
        filtered_instances << instance 
      end
    end
    filtered_instances
  end

  #
  # stopping / starting
  #
  def stop_instances(instances)
    instances_to_stop = Array.new
    
    instances.each do |i|
      instances_to_stop << i.instance_id if i.running?
    end
    if instances_to_stop.size > 0
      puts "Stopping instances: " + instances_to_stop.inspect
      @ec2.stop_instances({:instance_id => instances_to_stop})
    else
      puts "No instances to stop"
    end
  end
  
  def start_instances(instances)
    instances_to_start = Array.new
    
    instances.each do |i|
      instances_to_start << i.instance_id if i.stopped?
    end
    if instances_to_start.size > 0
      puts "Starting instances: " + instances_to_start.inspect
      @ec2.start_instances({:instance_id => instances_to_start})
    else
      puts "No instances to start"
    end
  end
  
  def start_app_servers
    start_instances(get_app_instances)
  end

  def stop_app_servers
    stop_instances(get_app_instances)
  end
  
  def start_web_servers
    start_instances(get_web_instances)
  end

  def stop_web_servers
    stop_instances(get_web_instances)
  end
  
  def start_loadgen_servers
    start_instances(get_loadgen_instances)
  end

  def stop_loadgen_servers
    stop_instances(get_loadgen_instances)
  end
  
  def add_web_instances(num, zone, names, ami = DEFAULT_WEB_AMI)
    opts = {:image_id => ami, 
            :min_count => 1,
            :max_count => 1,
            :security_group => "WebGroup",
            :instance_type => "m1.xlarge",
            :availability_zone => zone,
            :monitoring_enabled => true
           }
    add_instances(num,names,'web',opts)
  end
  
  def add_app_instances(num, zone, names, ami = DEFAULT_APP_AMI)
    opts = {:image_id => ami, 
            :min_count => 1,
            :max_count => 1,
            :security_group => "AppGroup",
            :instance_type => "c1.xlarge",
            :availability_zone => zone,
            :monitoring_enabled => true
           }
    add_instances(num,names,'app',opts)
  end
  
  def add_loadgen_instances(num, zone, names, ami = DEFAULT_LOADGEN_AMI)
    opts = {:image_id => ami, 
            :min_count => 1,
            :max_count => 1,
            :security_group => "LoadGenGroup",
            :instance_type => "m2.xlarge",
            :availability_zone => zone,
            :monitoring_enabled => false
           }
    add_instances(num,names,'loadgen',opts)
  end
  
  def show_current_region
    # TODO: implement this somehow...
    puts "Not Yet Implemented... show_current_region"
  end
  
  def get_availability_zones
    zones = @ec2.describe_availability_zones["availabilityZoneInfo"]["item"]
  end
  
  private
  
  def get_instance_blob
    @ec2.describe_instances
  end
  
  def add_instances(num, names, role, opts)
     index = 0
     num.times do
       puts "creating #{role} instance #{index}: name = #{names[index]}..."
       response = @ec2.run_instances(opts)
       instance_id = response.instancesSet.item[0].instanceId
       puts " => instance Created: id=#{instance_id}"
       tagged = tag_instance(instance_id,[{'Name' => names[index]}, {'Role' => "#{role}"}])
       puts " => instance Tags Set." if tagged
       puts " => instance Tags NOT Set." if !tagged
       index += 1
     end
   end

   def tag_instance(instance_id, tags)
     tag_opts = {:resource_id => [instance_id], 
                 :tag => tags 
                }
     tagged = false
     
     3.times do
       begin
         @ec2.create_tags(tag_opts)
         tagged = true
         break
       rescue => ex
         puts "Exception creating tags."
         # most likely needs more time to AWS to record the instanceID, so just pause a sec
         sleep 1
       end
     end
     return tagged
   end
   
end

