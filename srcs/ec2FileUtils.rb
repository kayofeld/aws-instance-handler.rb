require 'base64'
require 'colorize'
require 'securerandom'

class EC2FileUtils
  def initialize(script_path)
    begin
      @head = "#! /bin/bash\n"
      @head << "mkdir -p /root/include\n"
      @head << "cd /root/include/\n"
    Dir["include/*"].each { | n |
      @head << "echo \"#{Base64.strict_encode64(File.read(n).chomp)}\" > /root/#{n}.base64\n"
      @head << "cat /root/#{n}.base64 | base64 --decode > /root/#{n}\n"
    }
    @body = File.read(script_path)
    @body.gsub! "\${name}", self.getName
    @body.slice! "#! /bin/bash"
    rescue
      puts "ERROR: files contained in \"Include \" are not all readable.".red
      exit 1
    end
  end

  def createFile
    begin
      filename = "#{SecureRandom.uuid}.sh"
      File.open(filename, "w") { | f | f.write("#{@head}\n#{@body}")}
      return filename
    rescue
      puts "Could not generate generic file".red
    end
  end
    
end
