#!/bin/env ruby
require 'tmpdir'
require 'fileutils'

label = ARGV[0]
urls = ARGV[1..-1]

unless urls && urls.length > 1
  puts "Usage:  upload.rb <label> <urls ...>"
  exit 1
end

puts "Using label '#{label}'"

scp_host = `rhc app show -pp | grep SSH:`.match(/SSH:\s+([^\s]+)$/)[1]

Dir.mktmpdir do |tmp|
  upload_dir = File.join(tmp, label)
  FileUtils.mkdir upload_dir

  Dir.chdir(upload_dir) do
    cmd = 'curl'
    urls.each {|url| cmd << " -O #{url}"}
    puts "Downloading #{urls.length} files to #{tmp}..."
    puts `#{cmd} 2>&1`

    puts "Uploading #{urls.length} files to #{scp_host}..."
    cmd = "scp -r #{upload_dir} #{scp_host}:~/app-root/data/uploads/#{label}"
    puts `#{cmd} 2>&1`

    puts "Marking upload ready..."
    puts `ssh #{scp_host} "touch ~/app-root/data/uploads/#{label}/upload.ready" 2>&1`
  end
end

puts "Done."
