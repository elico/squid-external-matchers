#!/usr/bin/env ruby
# encoding: utf-8

require "rubygems"
require "open-uri"
require "syslog"

trap "SIGINT" do
  STDERR.puts "STDERR: Exiting"
  exit 130
end

$urls = []
$urls_regex = []

$urls_map_file_name = "/var/yt-classifier/lists/bump/urls"

$line_regex = /(#{URI.regexp})[\t]+([0-9]+)/

$urls_map_file_stat = File.stat($urls_map_file_name)

def readUrlsMapFile(mapfile)
  urls = []
  lines = File.readlines(mapfile)
  log("Mapfile #{$urls_map_file_name} lines #{lines.size}")
  lines.each do |line|
    line = line.strip
    next if line.empty?
    # URLS parsing
    begin
      ## What is the type of the domain? regexp? specific domain? root/parent domain ie prefix?
      # If starts with . prefix
      # If starts with / regex
      # else a single specific domain
      #
      # Validate if it's a valid domain name
      if line.start_with?(".")
        parse_res = URI.parse("http://#{line}/")
        urls << line 
        next       
      end
      
      parse_res = URI.parse("http://#{line}/")
      if !parse_res.nil?
        urls << line 
        next       
      end
      
      ## Default is url string and not regex
      if !matches[11].nil?
        if matches[11] == "1"
          url_type = "1"
        end
      end

      # if url_type == "1"
      #   $urls_regex
      #   matches[1]
      # end
      if url_type == "0"
        urls << matches[1]
      end
    rescue => e
      log("Error:#{e}")
      log("Error:#{e.inspect}")
    end
  end
  $urls_map_file_stat = File.stat($urls_map_file_name)
  $urls = urls

  log("new urls map size #{$urls.size}")
end

def urlTest(request)
  
  return if request == nil
  matched_to = []
  ret = 0
  if request.size > 0
    $urls.each do |url|
      log("Testing request => [ #{request} ] , against => #{url}") if $debug
      if request[1] == url
            matched_to << url
        ret = 1
        break
      end

      if url[0] == "."
        if request[1].end_with?(url)
          matched_to << url
          ret = 1
          break
        end
      end
    end
  end

    return { "res" => "#{ret}" ,"matched_to" => matched_to }
end

def answer(ans)
  log("Answer [ #{ans} ]") if $debug
  puts(ans)
end

def log(msg)
  Syslog.log(Syslog::LOG_ERR, "%s", msg)
  STDERR.puts("STDERR: [ #{msg} ]") if $debug
end

def conc(request)
  return unless request
  request = request.split
  if request.size > 1
    readUrlsMapFile($urls_map_file_name) if $urls_map_file_stat.mtime != File.stat($urls_map_file_name).mtime

    log("original request [#{request.join(" ")}].") if $debug

    res = "ERR"
    result = urlTest(request[1..-1])

    log("Results: #{result} , for dst => #{request[2]}") if $debug
    if result["ret"] == "1"
      answer("#{request[0]} OK")
    else
      answer("#{request[0]} ERR")
    end
  else
    log("original request [had a problem].") if $debug
    puts "ERR"
  end
end

def validr?(request)
  if request.ascii_only? && request.valid_encoding?
    true
  else
    STDERR.puts("errorness line [ #{request} ]")
    # sleep 2
    false
  end
end

def main
  Syslog.open("#{$PROGRAM_NAME}", Syslog::LOG_PID)
  log("Started with DEBUG => #{$debug}")
  readUrlsMapFile($urls_map_file_name)
  while request = gets
    request = request.strip
    next if request.empty?
    conc(request) if validr?(request)
  end
end

$debug = false
$debug = true

STDOUT.sync = true
main

