#! /usr/bin/env ruby

require './srcs/instances.rb'
require './srcs/ec2FileUtils.rb'
require 'json'

options = JSON.parse(File.open('deploy.config', 'r').read)

#Custom command to change root pass on machine
open(options["script_to_execute"], "a") {|f| f.puts "\necho \"root:#{options["root_passwd"]}\" | chpasswd"}

puts "hello"
  
options["script_to_execute"] = EC2FileUtils.new(options["script_to_execute"]).createFile
a = InstanceHandler.new(options)

puts "Return to deploy the VM"
gets
a.createVM
puts "VM correctly deployed"
puts "Return to destroy"
gets
a.destroy
puts "Destruction ended correctly"
puts "return to exit"
gets



