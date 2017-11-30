require 'aws-sdk'
require 'colorize'
require 'base64'

class   InstanceHandler

  # Constructor
  def initialize(options)
    @ec2                = Aws::EC2::Resource.new(region: options["region"])
    @client             = Aws::EC2::Client.new

    @options            = options
    
    @account_id         = options["account_id"]
    @image_id           = options["ami_id"]
    @key_name           = options["key_name"]
    @region             = options["region"]
    @script_path        = options["script_to_execute"]
    @server_type        = options["server_type"]
    @vpc_cidr_block     = options["vpc_cidr_block"]

    @batch_created      = false
    @nsg_created        = false
    @subnet_created     = false
    @vpc_created        = false
    @ip_associated      = false
  end # initialize

  
  def createVM
    if (@options["vpc"] == "new")
      self.create_vpc
    end
    if (@options["gateway"] == "new")
      self.create_gateway
    end
    if (@options["route"] == "new")
      self.create_route
    end
    if (@options["subnet"] == "new")
      self.create_subnet
    end
    if (@options["nsg"] == "new")
      self.create_nsg
    end
    self.create_instance
    if (@options["static_ip"] == "yes")
      self.allocate_associate_ip
    end
  end # CreateVM
  
  def destroy
    puts "destroying everything"
    if (@batch_created)
      self.destroy_batch
    end
    if (@ip_associated)
      self.release_address
    end
    if (@nsg_created)
      self.destroy_nsg
    end
    if (@vpc_created)
      self.destroy_vpc
    end
    exit 1
  end # destroy

  ####################
  # Creation methods #
  ####################

  def create_vpc
    begin # VPC Creation
      puts "creating vpc"
      @vpc = @ec2.create_vpc(
        {
          cidr_block: "#{options["vpc_cidr_block"]}"
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
  
  def allocate_associate_ip
    puts "Allocating ip"
    begin                      
      @addr = @client.allocate_address(
        {
          domain: "vpc"
        }
      )
      puts "Allocation id: #{@addr.allocation_id}"
      puts "Associating ip with VM"
      @client.associate_address(
        {
        allocation_id: @addr.allocation_id,
        instance_id: @instance[0].id
        }
      )
      @ip_associated = true
      puts "SUCCESS: Address associated: associated address: #{@addr.public_ip}".green
    rescue
      puts "ERROR: could not allocate or associate address".red
      self.destroy
      exit 1
    end  # ip allocation    
  end # create_allocate_ip


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
   end # nsg creation
  end # create_nsg

  def create_subnet
    begin # subnet creation

      puts "creating subnet"
      @subnet = @ec2.create_subnet(
        {
          vpc_id: @vpc.id,
          cidr_block: options["subnet_cidr_block"],
          availability_zone: options["availability_zone"]
        }
      )
      @subnet.create_tags(
        {
          tags:
            [
              {
                key: 'Name',
                value: "#{options["project_name"]}Subnet"
              }
            ]
        }
      )
      puts "SUCCESS: Subnet created: subnet id: #{@subnet.id}".green
      @subnet_created = true
    rescue
      puts "ERROR: could not create subnet".red
      self.destroy
    end # Subnet creation
  end # create_subnet

  def create_gateway
    puts "Creating gateway"
    begin # gateway creation
      @igw = @client.create_internet_gateway()[:internet_gateway]
      @client.attach_internet_gateway(
        {
          :internet_gateway_id => @igw[:internet_gateway_id],  
          :vpc_id => @vpc.id
        }
      )
      puts "SUCCESS: Gateway created".green
    rescue
      puts "ERROR: Failed to create gateway".red
      self.destroy
    end # gateway creation
  end # create_gateway

  def create_route
    puts "Creating routing table"
    begin
      @route = @ec2.create_route_table({vpc_id: @vpc.id})
      puts "SUCCESS: routing table initialized. id: #{@route.id}".green
      puts "Creating route"
      @client.create_route(
        {
          destination_cidr_block: "0.0.0.0/0",
          gateway_id: @igw.internet_gateway_id,
          route_table_id: @route.id,
        }
      )
      puts "SUCCESS: route created".green
    rescue
      puts "ERROR: Failed to create route".red
      self.destroy
    end # route creation
  end # create_route

  
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

  def destroy_subnet
    puts "Deleting subnet"
    begin
      @subnet.delete
      puts "SUCCESS: subnet deleted".green
    rescue
      puts "ERROR: Problem deleting subnet #{@subnet.id}".red
    end
  end # destroy_subnet

  def release_address
    puts "Releasing allocated IP address"
    begin
      @client.release_address(
        {
          allocation_id: @addr.allocation_id
        }
      )
      puts "SUCCESS: Address successfully released".green
    rescue
      puts "ERROR: Could not release address".red
    end
  end # release_address

  
  def destroy_vpc
    puts "Deleting VPC"
    begin
      @vpc.delete
      puts "SUCCESS: VPC deleted".green
    rescue
      puts "ERROR: Problem deleting vpc #{@vpc.id}".red
    end
  end # destroy_vpc

  def destroy_gateway
    begin
      @ec2.delete_internet_gateway(
        {
          internet_gateway_id: @igw.internet_gateway_id
        }
      )
    rescue
      puts "ERROR: Could not delete internet gateway".red
    end
    
  end # destroy_gateway

  def destroy_route
    begin
      puts "Deleting route table"
      @ec2.delete_route_table(
        {
          route_table_id: route_table_id
        }
      )
      puts "SUCCESS: route table deleted".green
    rescue
      puts "ERROR: Could not delete route table".red
    end
  end # destroy_route  
  
end #   Class InstanceHandler
