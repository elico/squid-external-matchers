#!/usr/bin/env ruby

require "socket"
require "thread"
require "syslog"
require "rubygems"
require "open-uri"
require "ipaddress"

$my_dir = __dir__
$regexes = []

$debug = false
$debug = true

socket_type = "tcp"
socket_address = "localhost"
port = 20001

trap "SIGINT" do
  STDERR.puts "STDERR: Exiting"
  exit 130
end

$regexes_map_file_name = "#{$my_dir}/var/regex"
if !ARGV[0].nil?
  $regexes_map_file_name = ARGV[0]
end

if !ARGV[1].nil?
  if ARGV[1].start_with?("unix:/")
    socket_type = "unix"
    unix_socket_url = URI.parse(ARGV[1])
    socket_address = unix_socket_url.path
  end
end

$value_location = 2

$line_regex = /^([a-zA-Z0-9\-\_\.]+)([\s\t\r\n]+)/

$regexes_map_file_stat = File.stat($regexes_map_file_name)

def cleanupUnixSocket(unix_socket_address)
  if File.exist?(unix_socket_address)
    File.delete(unix_socket_address)
  end
end

$regexline = /^\/.*\/$/

def readRegexpMapFile(mapfile)
  regexses = []
  lines = File.readlines(mapfile)
  log("Mapfile #{$regexes_map_file_name} lines #{lines.size}")
  lines.each do |line|
    line = line.strip
    next if line.empty?
    # LINE parsing
    begin
      #if line =~ $regexline
      single_regex = Regexp.new(line)
      regexses << single_regex
      log("Parsed Regex : #{single_regex.source}")
      #end
    rescue => e
      log("Error:#{e}")
      log("Error:#{e.inspect}")
    end
  end
  $regexes_map_file_stat = File.stat($regexes_map_file_name)
  $regexes = regexses

  log("new regexes map size #{$regexes.size}")
end

def requestTest(request)
  return if request == nil
  request = request.split
  matched_to = []
  ret = 0
  log("Request size: #{request.size} , value_location #{$value_location}")
  if request.size >= $value_location
    log("$Regexes size #{$regexes.size}")
    $regexes.each do |single_regex|
      log("Testing request => [ #{request} ] , against => #{single_regex.source}") if $debug
      log("Testing request => [ #{request[$value_location]} ] , against => #{single_regex.source}") if $debug
      if request[$value_location] =~ single_regex
        matched_to << single_regex
        ret = 1
        break
      end
    end
  end
  return { "request_id" => request[0], "ret" => "#{ret}", "matched_to" => matched_to }
end

def log(msg)
  Syslog.log(Syslog::LOG_ERR, "%s", msg)
  STDERR.puts("STDERR: [ #{msg} ]") if $debug
end

def validr?(request)
  if request.ascii_only? && request.valid_encoding?
    return true
  else
    STDERR.puts("errorness line [ #{request} ]")
    return false
  end
end

STDOUT.sync = true
Syslog.open("#{$PROGRAM_NAME}", Syslog::LOG_PID)
log("Started with DEBUG => #{$debug}")

reloader = Thread.new do
  readRegexpMapFile($regexes_map_file_name)

  loop do
    if $regexes_map_file_stat.mtime != File.stat($regexes_map_file_name).mtime
      readRegexpMapFile($regexes_map_file_name)
    end
    sleep 3
  end
end

answers = { "0" => "ERR", "1" => "OK" }

case socket_type

when /^tcp/i
  begin
    puts "Trying to bind: #{socket_address}:#{port}"
    server_socket = TCPServer.new(socket_address, port)

    loop do
      Thread.start(server_socket.accept) do |s|
        log("#{s} is accepted")
        processingtQueue = Queue.new

        proccessor = Thread.new do
          loop do
            incomming_request = processingtQueue.pop
            return if incomming_request.nil?
            Thread.new do
              result = requestTest(incomming_request) if validr?(incomming_request)
              s.puts("#{result["request_id"]} #{answers[result["ret"]]}")
              log("result for request: #{s} => [ #{incomming_request} ] , res => #{result}") if $debug
            end
          end
        end

        while line = s.gets
          processingtQueue << line.strip.chomp
          log("original request: #{s} => [ #{line.chomp} ]") if $debug
        end
        proccessor.join
        log("#{s} is gone")
        s.close
      end
    end
  rescue => e
    puts e
    puts e.inspect
    exit 10
  end
when /^unix/i
  begin
    if IPAddress.valid?(socket_address)
      puts "Cannot use IP address #{socket_address} for unix socket"
      exit 1
    end
    unix_socket_address = socket_address

    cleanupUnixSocket(unix_socket_address)
    server_socket = UNIXServer.new(unix_socket_address)
    loop do
      Thread.start(server_socket.accept) do |s|
        log("#{s} is accepted")
        while line = s.gets
          line = line.strip.chomp
          log("original request: #{s} => [ #{line} ]") if $debug
          result = requestTest(line) if validr?(line)
          s.puts("#{result["request_id"]} #{answers[result["ret"]]}")
          log("result for request: #{s} => [ #{line} ] , res => #{result}") if $debug
        end
        log("#{s} is gone")
        s.close
      end
    end
  rescue => e
    File.delete(unix_socket_address)
    puts e
    puts e.inspect
    exit 11
  end
else
  puts "Sokcet type: #{socket_type}  is not supported"
  exit 1
end

reloader.join
