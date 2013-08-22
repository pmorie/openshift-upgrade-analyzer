#!/bin/env ruby
require 'fileutils'

def import
  repo_dir = ENV['OPENSHIFT_REPO_DIR']
  data_dir = ENV['OPENSHIFT_DATA_DIR']
  uploads_dir = File.join(data_dir, 'uploads')
  upgrade_tool = File.join(repo_dir, 'upgrade_tool.rb')

  FileUtils.mkdir(uploads_dir) unless Dir.exists?(uploads_dir)

  Dir.glob(File.join(uploads_dir, '**/*.ready')).each do |marker|
    upload_dir = File.dirname(marker)

    if Dir.glob(File.join(upload_dir, '*.tar.gz')).length > 0
      log "Importing files from #{upload_dir}"

      out_file = File.join(upload_dir, "#{File.basename(upload_dir)}.json")

      output = ''
      begin
        log "Combining files into #{out_file}"
        output, exit_code = run "#{upgrade_tool} combine --files #{File.join(upload_dir, '*.tar.gz')} --out #{out_file} 2>&1"
        raise "Non-zero exit code: #{exit_code}" unless exit_code == 0

        log output

        log "Persisting #{out_file}"
        output, exit_code = run "#{upgrade_tool} persist-mongo --file #{out_file} 2>&1"
        raise "Non-zero exit code: #{exit_code}" unless exit_code == 0

        log output
      rescue => e
        log "Failed to import files from #{upload_dir}: #{e.message}\nTool output: #{output}"
      end
    else
      log "WARNING: No tarballs found in #{upload_dir}"
    end

    FileUtils.mv marker, File.join(upload_dir, 'upload.done')
    log "Import of #{upload_dir} finished"
  end
end

def run(cmd)
  log "Executing command: #{cmd}"
  output = `#{cmd}`
  exit_code = $?.exitstatus
  return [output, exit_code]
end

def log(msg)
  log_file = "/tmp/import.log"
  timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")

  FileUtils.touch log_file unless File.exists?(log_file)

  file = File.open(log_file, 'a')
  begin
    file.puts "#{timestamp} #{msg}"
  ensure
    file.close
  end
end

import
