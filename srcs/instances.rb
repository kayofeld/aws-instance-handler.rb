require 'aws-sdk'
require 'colorize'
require 'base64'

class   InstanceHandler

  # Constructor
  def initialize(options)
    @options = options
    @key_name = options["key_name"]
    @server_type = options["server_type"]
    @region = options["region"]
    @ec2 = Aws::EC2::Resource.new(region: options["region"])
    @client = Aws::EC2::Client.new
    @account_id = options["account_id"]
    @image_id = options["ami_id"]
    @script_path = options["script_to_execute"]
    @batch_created = false
    @nsg_created = false
    @vpc_created = false
  end # initialize

  
  def createVM
    if (@options["vpc"] == "new")
      self.create_vpc
    end
    if (@options["nsg"] == "new")
      self.create_nsg
    end
    self.create_instance
  end # CreateVM
  
  def destroy
    puts "destroying everything"
    if (@batch_created)
      self.destroy_batch
    end
    if (@nsg_created)
      self.destroy_nsg
    end
    if (@vpc_created)
      self.destroy_vpc
    end
  end # destroy

  ####################
  # Creation methods #
  ####################

  def create_vpc
    begin # VPC Creation
      puts "creating vpc"
      @vpc = @ec2.create_vpc(
        {
          cidr_block: "10.0.0.0/16"
        }
      )
      
      @vpc.modify_attribute(
        {
          enable_dns_support:
            {
              value: true
            }
        }
      )
      @vpc.modify_attribute(
        {
          enable_dns_hostnames:
            {
              value: true
            }
        }
      )
      @vpc.create_tags(
        {
          tags:
            [
              {
                key: 'Name',
                value: "#{options["project_name"]}_VPC"
              }
            ]
        }
      )
      puts "SUCCESS: vpc created: vpc id: #{@vpc.id}".green
      @vpc_created = true
    rescue
      puts "ERROR: could not create VPC".red
      exit 1
    end # VPC Creation
  end # create_vpc

  def create_nsg
    begin # fetch vpc id
      vpc_id = @vpc.id
    rescue
      vpc_id = nil
    end
   begin # nsg creation
      puts "creating nsg"
      @security = @ec2.create_security_group(
        {
          description: "Test NG, to delete",
          group_name: "#{@options["project_name"]}NSG",
          vpc_id: (vpc_id if @vpc_created)
        }.delete_if{ |k,v| v.nil? }
      )
      
      ec2Client = Aws::EC2::Client.new(region: @region)
      ec2Client.authorize_security_group_ingress(
        {
          group_id: @security.id,
          ip_permissions: [
            {
              ip_protocol: 'UDP',
              from_port: 5040,
              to_port: 5040,
              ip_ranges: [
                {
                  cidr_ip: "0.0.0.0/0",
                }
              ]
            },
            {
              ip_protocol: 'TCP',
              from_port: 5050,
              to_port: 5050,
              ip_ranges: [
                {
                  cidr_ip: "0.0.0.0/0",
                }
              ]
            },
            {
              ip_protocol: 'TCP',
              from_port: 22,
              to_port: 22,
              ip_ranges: [
                {
                  cidr_ip: "0.0.0.0/0",
                }
              ]
            },
            {
              ip_protocol: 'UDP',
              from_port: 10000,
              to_port: 64000,
              ip_ranges: [
                {
                  cidr_ip: "0.0.0.0/0",
                }
              ]
            },
            {
              ip_protocol: 'UDP',
              from_port: 5060,
              to_port: 5060,
              ip_ranges: [
                {
                  cidr_ip: "0.0.0.0/0",
                }
              ]
            },
            {
              ip_protocol: 'TCP',
              from_port: 9090,
              to_port: 9090,
              ip_ranges: [
                {
                  cidr_ip: "0.0.0.0/0",
                }
              ]
            },
            {
              ip_protocol: 'TCP',
              from_port: 5040,
              to_port: 5040,
              ip_ranges: [
                {
                  cidr_ip: "0.0.0.0/0",
                }
              ]
            },
            {
              ip_protocol: 'TCP',
              from_port: 443,
              to_port: 443,
              ip_ranges: [
                {
                  cidr_ip: "0.0.0.0/0",
                }
              ]
            },
            {
              ip_protocol: 'UDP',
              from_port: 5050,
              to_port: 5050,
              ip_ranges: [
                {
                  cidr_ip: "0.0.0.0/0",
                }
              ]
            },
            {
              ip_protocol: 'TCP',
              from_port: 5060,
              to_port: 5061,
              ip_ranges: [
                {
                  cidr_ip: "0.0.0.0/0",
                }
              ]
            },
            {
              ip_protocol: 'TCP',
              from_port: 80,
              to_port: 80,
              ip_ranges: [
                {
                  cidr_ip: "0.0.0.0/0",
                }
              ]
            },            
          ]
        }
      )
      puts "SUCCESS: Nsg created: nsg id: #{@security.id}".green
      @nsg_created = true
   rescue
     puts "ERROR: Could not create NSG".red
     self.destroy
     exit 1
   end # nsg creation
  end # create_nsg
  
  def create_instance
    begin # Instance creation
      puts "creating instance"
      if (@nsg_created)
        id_nsg = @security.id
      else
        id_nsg = @options["nsg"]
      end
      begin
        puts @script_path
        user_data = Base64.encode64(File.read(@script_path)).chomp
      rescue Errno::ENOENT
        puts "ERROR: Script path invalid".red
        puts "Continue deployment ? (y/N)"
        response = gets.chomp.capitalize # don't want a \n here
        if (response != "Y")
          self.destroy
          exit 1
        end
        user_data = nil
      end
        
      @instance = @ec2.create_instances(
        {
          image_id: "#{@image_id}",
          min_count: 1,
          max_count: 1,
          key_name: "#{@key_name}",
          security_group_ids:
            [
              id_nsg
            ],
          instance_type: "#{@server_type}",
          placement:
            {
              availability_zone: @options["availability_zone"]
            },
          iam_instance_profile: {
            name: "ssmrole",
          },
          user_data: user_data
        }.delete_if{ |k, v| v.nil? }
      )

      @ec2.client.wait_until(:instance_status_ok, {instance_ids: [@instance[0].id]})

      @instance.batch_create_tags(
        {
          tags: [
            {
              key: 'Name',
              value: "#{@options["project_name"]}Instance"
            },
            {
              key: 'Group',
              value: "#{@options["project_name"]}Group"
            }
          ]
        }
      )
      puts "SUCCESS: Instance created: intance id: #{@instance[0].id}".green
      @batch_created = true
    rescue                     
      puts "ERROR: could not create instance".red
      self.destroy
      exit 1
    end # Instance creation
  end # create_instance

  #######################
  # Destruction methods #
  #######################
  
  def destroy_batch
    puts "Shutting down instance"
    begin
      @instance.batch_stop
      puts "Terminating Instance"
      @instance.batch_terminate!
      @ec2.client.wait_until(:instance_terminated, {instance_ids: [@instance[0].id]}) do | wait |
        wait.interval = 0
        wait.before_wait do | n, resp |
          sleep(n ** 2)
        end
      end
      puts "SUCCESS: Instance deleted".green
    rescue
      puts "ERROR: Problem while deleting instance #{@instance[0].id}".red
    end
  end # destroy_batch

  def destroy_nsg
    puts "Deleting nsg"
    begin
      @security.delete
      puts "SUCCESS: NSG deleted".green
    rescue
      puts "ERROR: Error while deleting #{@security.id}".red
    end
  end # destroy_nsg

  def destroy_vpc
    puts "Deleting VPC"
    begin
      @vpc.delete
      puts "SUCCESS: VPC deleted".green
    rescue
      puts "ERROR: Problem deleting vpc #{@vpc.id}".red
    end
  end # destroy_vpc
end #   Class InstanceHandler
