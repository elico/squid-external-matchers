#!/usr/bin/env ruby
# encoding: utf-8

require "rubygems"
require "open-uri"
require "syslog"
require "thread"

trap "SIGINT" do
  STDERR.puts "STDERR: Exiting"
  exit 130
end

$queue = Queue.new

$my_dir = __dir__
$domains = []

$domains_map_file_name = "#{$my_dir}/var/yt-classifier/lists/bump/domains"
if !ARGV[0].nil?
  $domains_map_file_name = ARGV[0]
end

$line_regex = /^([a-zA-Z0-9\-\_\.]+)([\s\t\r\n]+)/

$domains_map_file_stat = File.stat($domains_map_file_name)

def readDomainssMapFile(mapfile)
  domains = []
  lines = File.readlines(mapfile)
  log("Mapfile #{$domains_map_file_name} lines #{lines.size}")
  lines.each do |line|
    line = line.strip
    next if line.empty?
    # LINE parsing
    begin
      if line.start_with?(".")
        parse_res = URI.parse("http://#{line}/")
        domains << line
        next
      end

      parse_res = URI.parse("http://#{line}/")
      if !parse_res.nil?
        domains << line
        next
      end
    rescue => e
      log("Error:#{e}")
      log("Error:#{e.inspect}")
    end
  end
  $domains_map_file_stat = File.stat($domains_map_file_name)
  $domains = domains

  log("Loaded new domains map file, number of domains: #{$domains.size}")
end

def requestTest(request)
  return if request == nil
  matched_to = []
  ret = 0
  if request.size > 0
    $domains.each do |domain|
      log("Testing request => [ #{request} ] , against => #{domain}") if $debug
      if domain[0] == "."
        if request[1].end_with?(domain) or request[1] == domain[1..-1]
          matched_to << domain
          ret = 1
          break
        end

        if request[1] == domain
          matched_to << domain
          ret = 1
          break
        end
      end
    end
  end
  return { "res" => "#{ret}", "matched_to" => matched_to }
end

def answer(ans)
  log("Answer [ #{ans} ]") if $debug
  STDOUT.puts(ans)
end

def log(msg)
  Syslog.log(Syslog::LOG_ERR, "%s", msg)
  STDERR.puts("STDERR: [ #{msg} ]") if $debug
end

def conc(request)
  return unless request
  request = request.split
  if request.size > 1
    log("original request [#{request.join(" ")}].") if $debug

    res = "ERR"
    result = requestTest(request[1..-1])

    log("Results: #{result} , for dst => #{request[2]}") if $debug
    if result["res"] == "1"
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

$debug = false
$debug = true

STDOUT.sync = true

Syslog.open("#{$PROGRAM_NAME}", Syslog::LOG_PID)
log("Started with DEBUG => #{$debug}")
readDomainssMapFile($domains_map_file_name)

reloader = Thread.new do
  loop do
    if $domains_map_file_stat.mtime != File.stat($domains_map_file_name).mtime
      readDomainssMapFile($domains_map_file_name)
    end
    sleep 3
  end
end

consumer = Thread.new do
  loop do
    request = $queue.pop
    conc(request) if validr?(request)
    exit if request.nil?
  end
end

producer = Thread.new do
  while line = STDIN.gets
    $queue << line if line
  end
end

consumer.join
reloader.join
# producer.join
