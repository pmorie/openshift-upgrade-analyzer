#!/bin/env ruby
require 'tmpdir'
require 'fileutils'
require 'uri'
require 'pty'

label = ARGV[0]
urls = ARGV[1..-1]

unless urls && urls.length > 1
  puts "Usage:  upload.rb <label> <urls ...>"
  exit 1
end

def run_cmd(cmd, msg = nil)
  puts msg if msg
  begin
    PTY.spawn( cmd ) do |stdin, stdout, pid|
      begin
        # Do stuff with the output here. Just printing to show it works
        stdin.each { |line| print line }
      rescue Errno::EIO
      end
    end
  rescue PTY::ChildExited
  end
end

puts "Using label '#{label}'"

ssh_info = `rhc apps`.scan(/Git URL:\s+(.*)\n\s+Initial Git URL:.*openshift-upgrade-analyzer.git/).flatten.map{|x| URI.parse(x) }.first
scp_host = "#{ssh_info.user}@#{ssh_info.host}"

Dir.mktmpdir do |tmp|
  upload_dir = File.join(tmp, label)
  FileUtils.mkdir upload_dir

  Dir.chdir(upload_dir) do
    cmd = 'curl'
    urls.each {|url| cmd << " -O #{url}"}
    run_cmd cmd, "Downloading #{urls.length} files to #{tmp}..."

    cmd = "scp -r #{upload_dir} #{scp_host}:~/app-root/data/uploads/#{label}"
    run_cmd cmd, "Uploading #{urls.length} files to #{scp_host}..."

    cmd = "ssh #{scp_host} 'touch ~/app-root/data/uploads/#{label}/upload.ready' 2>&1"
    run_cmd cmd, "Marking upload ready..."
  end
end

puts "Done."
