#!/usr/bin/env ruby

require "socket"
require "thread"
require "syslog"
require "rubygems"
require "open-uri"
require "ipaddress"

$my_dir = __dir__
$yt_vids = []

$debug = false
# $debug = true

socket_type = "unix"
socket_address = "unix:/tmp/youtube-filter"
port = 20001

trap "SIGINT" do
  STDERR.puts "STDERR: Exiting"
  exit 130
end

$yt_vids_map_file_name = "#{$my_dir}/var/youtube-vids"
if !ARGV[0].nil?
  $yt_vids_map_file_name = ARGV[0]
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

$vids_map_file_stat = File.stat($yt_vids_map_file_name)
$vidline = /^([a-zA-Z0-9\_\-]{11})$/
$yt_vid = /([a-zA-Z0-9\_\-]{11})/

$yt_vids_regexese = []
$yt_vids_regexese << { "regexp" => Regexp.new("^http(s)?:\/\/(www.)?youtube.com\/watch\\?v=(#{$yt_vid.source})"), "vid_pos" => 3 }
$yt_vids_regexese << { "regexp" => Regexp.new("^http(s)?:\/\/(www.)?youtu.be\/(#{$yt_vid.source})"), "vid_pos" => 2 }
$yt_vids_regexese << { "regexp" => Regexp.new("^http(s)?:\/\/([a-zA-Z0-9_-]+.)?ytimg.com\/an_webp\/(#{$yt_vid.source})\/"), "vid_pos" => 3 }
$yt_vids_regexese << { "regexp" => Regexp.new("^http(s)?:\/\/([a-zA-Z0-9_-]+.)?ytimg.com\/vi\/(#{$yt_vid.source})\/"), "vid_pos" => 3 }
# ([a-zA-Z0-9.]+.(jpg|webp)

def cleanupUnixSocket(unix_socket_address)
  if File.exist?(unix_socket_address)
    File.delete(unix_socket_address)
  end
end

def readVidsMapFile(mapfile)
  yt_vids = []
  lines = File.readlines(mapfile)
  log("Mapfile #{$yt_vids_map_file_name} lines #{lines.size}")
  lines.each do |line|
    line = line.strip
    next if line.empty?
    # LINE parsing
    begin
      if line =~ $vidline
        log("Valid VID : #{line}") if $debug
        yt_vids << line.chomp
      else
        log("INVALID VID : #{line}") if $debug
      end
      #end
    rescue => e
      log("Error:#{e}")
      log("Error:#{e.inspect}")
    end
  end
  $vids_map_file_stat = File.stat($yt_vids_map_file_name)
  $yt_vids = yt_vids

  log("new Youtube VIDS map size #{$yt_vids.size}")
end

def requestTest(request)
  return if request == nil
  request = request.split
  matched_to = []
  ret = 0
  log("Request size: #{request.size} , value_location #{$value_location}")
  if request.size >= $value_location
    log("$yt_vids size #{$yt_vids.size}")
    ## extract vid from:
    ## https://www.youtube.com/watch?v=###VID###
    ## https://youtu.be/###VID###
    ## https://i.ytimg.com/###VID###
    vid = ""
    $yt_vids_regexese.each do |regex|
      log("Testing #{request[$value_location]} , against => #{regex}")
      if request[$value_location] =~ regex["regexp"]
        log("MATCH #{request[$value_location]} , against => #{regex} , last_match => #{Regexp.last_match.inspect}")
        vid = Regexp.last_match(regex["vid_pos"])
        break
      end
    end
    if $yt_vids.include?(vid)
      ret = 1
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
  readVidsMapFile($yt_vids_map_file_name)

  loop do
    if $vids_map_file_stat.mtime != File.stat($yt_vids_map_file_name).mtime
      readVidsMapFile($yt_vids_map_file_name)
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
