#!/usr/bin/env ruby

require "yaml"
require "diffy"
require "open-uri"
require "uri/http"

begin
  sites = YAML::load(File.open('sites.yml'))['sites']
  config = YAML::load(File.open('config.yml'))
rescue Errno::ENOENT => e
  puts e.message
  exit
end

user_agent = config['user-agent'] || "WebDiffy Bot"
css = config['css']

def data_file(id) "data/#{id}.html" end
def log_file(id) "log/#{id}.html" end

sites.each do |site|
  puts "Inspecting: #{site}"
  id = (URI.parse(site).host + URI.parse(site).path)
         .downcase
         .gsub(/^www\./, "")   # remove www
         .gsub(/\/$/, "")      # remove trailing /
         .gsub(/[\.\/]/, "_")  # seperate everything with underscores

  begin
    current_html = open(site, "User-Agent" => user_agent).read
                     .gsub(/\(<[^\/]\)/, "\n\1")           # add some newlines to break tags up for diff
                     .gsub(/<head.*<\/head>/m, "")         # remove the head
                     .gsub(/<script(.*?)<\/script>/m, "")  # remove script tags

    if File.file? data_file(id)
      past_html = File.open(data_file(id), "r").read
      if past_html != current_html
        # log diff
        diff = Diffy::Diff.new(past_html, current_html, :context => 0).to_s(:html_simple)

        # TODO: fix this hack for a blank diff
        next if diff == "<div class=\"diff\"></div>"

        if File.file? log_file(id)
          log = IO.read log_file(id)
          IO.write log_file(id), "<h3>#{Time.now}</h3>\n#{diff}\n<hr>\n" + log
        else
          File.open(log_file(id), "w") {|f| f.puts "<h3>#{Time.now}</h3>\n#{diff}\n<hr>\n\n<style>\n#{Diffy::CSS}#{css}</style>"}
        end

        # update the current file
        File.open(data_file(id), "w") {|f| f.puts current_html}
      end
    else
      File.open(data_file(id), "w") {|f| f.puts current_html}
    end
  rescue
    puts "Couldn't handle: #{site}"
  end
end
