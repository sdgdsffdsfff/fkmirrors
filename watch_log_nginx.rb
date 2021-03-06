#!/usr/bin/env ruby
require "rubygems"
require "filewatch/tail"
require 'uri'

class LogLine
  def initialize(line)
    @origin_line = line
    @size = 0
    @line_parts = []
    parse_origin_line
  end
  
  def parse_origin_line
    return if @origin_line.nil? or @origin_line.empty?
    quoted_word = ""
    inside_quotes = false 
    @origin_line.split.each { |word|
      if word[0]=='"' and word[word.size-1] != '"'
        quoted_word = quoted_word + " " + word
        inside_quotes = true 
      elsif  word[0]!='"' and word[word.size-1] == '"'
        quoted_word = quoted_word + " " + word
        @line_parts << quoted_word.strip
        quoted_word = ""
        inside_quotes = false 
      elsif inside_quotes
        quoted_word = quoted_word + " " + word
      else
        @line_parts << word 
      end
    } 
  end
  
  def [](idx)
    return nil if idx < 0 or idx >= size
    return @line_parts[idx]
  end
  
  def size
    return @line_parts.size
  end
end

class String
  def rchomp(sep = $/)
    self.start_with?(sep) ? self[sep.size..-1] : self
  end
end

IP_CONFIG_FILE = '/www/wdlinux/nginx/conf/cloudflare.conf'
$domains = []
Dir["/www/wdlinux/nginx/conf/vhost/*.conf"].each do |filename|
      $domains << File.basename(filename, '.conf').downcase
end
#puts $domains
$blackips = []
$blackrefers = []
$begintime = ARGV[0]
#puts $begintime
def check_line(line)
  need_delete = false
  msg =''
  log = LogLine.new(line)
  ip = log[0]
  ua = log[9].downcase
  uri = log[5]
  refer = log[8].downcase
  puts line if uri.include?('fkmirrors')
  if uri.include?('fkmirrors')
    need_delete = true
    msg = 'fkmirrors server ip'
  elsif (ua.include?('winhttp') && refer=='"-"' && !(line.include?('admin') || line.include?('configuration') || line.include?('server_info'))) || (ua=='"-"' && refer=='"-"')
    need_delete = true
    msg = 'WinHttp agent or no ua and no refer'
  elsif ua.include?('googlebot')
    unless `host #{ip}`.include?('googlebot.com')
      msg = 'fake googlebot'
      need_delete = true
    end
  elsif ua.include?('baiduspider')
    unless `host #{ip}`.include?('baidu.com')
      msg = 'fake baiduspider'
      need_delete = true
    end
  elsif (uri.include?('.css') || uri.include?('.jpg') || uri.include?('.js'))&& refer.size>5
    unless $domains.detect{|d| refer.include?(d)}
    u = URI(refer.rchomp('"').chomp('"'))
    irefer = u.host+u.path
    unless $blackrefers.include?(irefer)
      $blackrefers << irefer
      puts "Found bad host: #{irefer} => #{uri}"
      if u.host.downcase.include?('google') && (u.path.size<3 || u.path.include?('blank.html'))
        need_delete = true
      else
        cmd="curl '#{irefer}?key=fkmirrors'"
        puts cmd
        `#{cmd}`
      end
    end
    msg = 'unknown host use css'
    end 
  end
  if need_delete && !$blackips.include?(ip)
    if ip.size>7
    unless `grep 'deny #{ip};' #{IP_CONFIG_FILE}`.include?("deny #{ip}")
    $blackips << ip
    puts '+'*40
    puts Time.now.to_s
    puts "block ip #{ip}, reson: #{msg}"
    puts line
    puts '-'*40
    
    #`iptables -I INPUT -s #{ip} -j DROP`
    `echo 'deny #{ip};' >> #{IP_CONFIG_FILE}; /etc/init.d/nginxd reload`
    end 
    end
  end
rescue => e
  puts "[ERROR] => #{line} #{e}"
end

if !$begintime
  t = FileWatch::Tail.new
  t.tail("/www/wdlinux/nginx/logs/access*.log")
  t.subscribe do |path, line|
    check_line(line)
  end
elsif ARGV[1]
    check_line(ARGV[0])
else
  File.open("/www/wdlinux/nginx/logs/access.log") do |file| 
    process = false
    file.each do |line|
      if process
        check_line(line)
      elsif line.include?($begintime)
        process = true
      end
    end 
  end 
end
