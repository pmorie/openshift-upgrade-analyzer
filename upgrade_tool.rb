#!/bin/env ruby

require 'rubygems/package'
require 'zlib'
require 'json'
require 'thor'
require 'fileutils'
require 'zlib'


class UpgradeAnalyzer
  def combine(files, output_file, mode = :all)
    raise "File list is required" unless files && files.length > 0
    raise "Output file #{output_file} already exists" if File.exists?(output_file)
    raise "Invalid mode #{mode}" unless [:all, :results, :errors].include?(mode)

    # expand wildcards
    if files.length == 1 && files[0].index('*')
      files = Dir.glob(files[0])
    end

    case mode
    when :all
      filter = "results|errors"
    when :errors
      filter = "errors"
    when :results
      filter = "results"
    end

    File.open("#{output_file}", 'w') do |f|
      gz = Zlib::GzipWriter.new(f)

      files.each do |file|
        unless file =~ /.*\.tar\.gz/
          puts "Skipping unrecognized file #{file}"
          next
        end

        puts "processing #{file}"

        tar_extract = Gem::Package::TarReader.new(Zlib::GzipReader.open(file))
        tar_extract.rewind # The extract has to be rewinded after every iteration
        tar_extract.each do |entry|
          next unless entry.file?

          filename = File.basename(entry.full_name)

          # skip archived results
          next if filename =~ /upgrade_(#{filter})_(.*)(_\d{4}-\d{2}-\d{2}(-\d{6})?)/

          next unless filename =~ /upgrade_(#{filter})_(.*)/

          puts "combining #{filename}"
          
          gz.write(entry.read)
        end
        tar_extract.close
      end

      gz.close
    end
  end

  def persist_mongo(file)
    raise "File #{file} not found" unless File.exists?(file)
    raise "File #{file} isn't a .json.gz file" unless File.basename(file).end_with?('.json.gz')

    require 'mongo'

    host = ENV['OPENSHIFT_MONGODB_DB_HOST']
    port = ENV['OPENSHIFT_MONGODB_DB_PORT']
    username = ENV['OPENSHIFT_MONGODB_DB_USERNAME']
    password = ENV['OPENSHIFT_MONGODB_DB_PASSWORD']
    db_name = ENV['OPENSHIFT_APP_NAME']
    collection_name = "upgrade_#{File.basename(file, '.json.gz')}"

    client = Mongo::MongoClient.new(host, port)
    db = client[db_name]
    db.authenticate(username, password)
    col = db[collection_name]

    puts "writing entries to #{db.name}.#{collection_name} from #{file}"

    records_written = 0
    File.open(file, 'r') do |f|
      gz = Zlib::GzipReader.new(f)
      gz.each_line do |line|
        entry = JSON.load(line)
        process_entry_for_mongo(entry)

        begin
          col.insert(entry)
          records_written += 1
        rescue => e
          puts "Failed to insert entry: #{entry.inspect}"
          puts e.message
          raise
        end
      end
      gz.close
    end

    puts "done; wrote #{records_written} records"
  end

  private

  def append_to_file(filename, value)
    FileUtils.touch filename unless File.exists?(filename)

    file = File.open(filename, 'a')
    begin
      file.puts value
    ensure
      file.close
    end
  end

  def process_entry_for_mongo(entry)
    return unless entry['remote_upgrade_result']

    if entry['remote_upgrade_result']['itinerary']
      processed_itinerary = {}

      entry['remote_upgrade_result']['itinerary'].each do |k, v|
        processed_itinerary[k.gsub('.', '_')] = v
      end

      entry['remote_upgrade_result']['itinerary'] = processed_itinerary
    end
  end
end

class AnalyzerCli < Thor
  desc "combine", "Combines output from upgrade logs in the provided tarballs and emits the JSON to a file"
  method_option :files, :type => :array, :required => true, :desc => "The tarball file(s) to combine (wildcards supported)"
  method_option :out, :type => :string, :required => true, :desc => "The combined output file"
  method_option :mode, :type => :string, :required => false, :default => "all", :desc => "results, errors, or all (default)"
  def combine
    UpgradeAnalyzer.new.combine(options.files, options.out, options.mode.to_sym)
  end

  desc "persist-mongo", "Writes the given upgrade .json file contents to an OpenShift mongodb instance (run this from a gear)"
  method_option :file, :type => :string, :required => true, :desc => "The upgrade file containing JSON entries"
  def persist_mongo
    UpgradeAnalyzer.new.persist_mongo(options.file)
  end
end

AnalyzerCli.start if __FILE__ == $0
