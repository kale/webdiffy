#!/usr/bin/env ruby

require "yaml"
require "diffy"
require "open-uri"
require "uri/http"
require "ostruct"
require "optparse"

module WebDiffy
  class App
    def initialize(*args)
      @args = args

      @config = OpenStruct.new
      config_file = (YAML::load(File.open("config.yml")) if File.exists? "config.yml") || Hash.new

      @config.user_agent = config_file['user-agent'] || "WebDiffy Tool"
      @config.css = "#{Diffy::CSS}\n#{config_file['css']}" || Diffy::CSS
      @config.context = 0
      @config.data_path = "data"
      @config.log_path = "log"
      @config.format = :color
      @config.log_blanks = false
    end

    def run
      if parsed_options? && arguments_valid?
        if @args.count == 2
          site1 = open(@args[0]).read
          site2 = open(@args[1]).read
          puts Diffy::Diff.new(site1, site2, :context => @config.context).to_s(@config.format)
        elsif @args.count == 1
          process_sites @args
        elsif @config.sites
          process_sites @config.sites
        end
      else
        abort @opts.to_s
      end
    end

    def log_diff(id, diff)
      if File.file? log_file(id)
        # append to the top of the file
        log = IO.read log_file(id)
        IO.write log_file(id), "<h3>#{Time.now}</h3>\n#{diff}\n<hr>\n" + log
      else
        File.open(log_file(id), "w") {|f| f.puts "<h3>#{Time.now}</h3>\n#{diff}\n<hr>\n\n<style>\n#{@config.css}</style>"}
      end

      File.open(log_file_today, "a") {|f| f.puts "<h3>#{id} | #{Time.now}</h3>\n#{diff}\n<hr>\n\n<style>\n#{@config.css}</style>"}
    end

    def process_sites(sites)
      sites.each do |site|
        puts "Inspecting: #{site}"
        id = (URI.parse(site).host + URI.parse(site).path)
              .downcase
              .gsub(/^www\./, "")   # remove www
              .gsub(/\/$/, "")      # remove trailing /
              .gsub(/[\.\/]/, "_")  # seperate everything with underscores

        begin
          current_html = open(site, "User-Agent" => @config.user_agent).read
                          .gsub(/</, "\n<")                     # add some newlines to break tags up for diff
                          .gsub(/>/, ">\n")                     # add some newlines to break tags up for diff
                          .gsub(/<head.*<\/head>/m, "")         # remove the head
                          .gsub(/<script(.*?)<\/script>/m, "")  # remove script tags
                          .gsub(/^[\s]*$\n/, "")                # remove blank lines

          if File.file? data_file(id)
            past_html = File.open(data_file(id), "r").read
            if past_html != current_html
              # log diff
              diff = Diffy::Diff.new(past_html, current_html, :context => 0).to_s(:html)

              # TODO: fix this hack for a blank diff
              next if diff == "<div class=\"diff\"></div>"

              log_diff(id, diff)

              # update the current file
              File.open(data_file(id), "w") {|f| f.print current_html}
            elsif @config.log_blanks
              log_diff(id, "")
            end
          else
            File.open(data_file(id), "w") {|f| f.print current_html}
          end
        rescue StandardError => e
          puts "Couldn't handle #{site}: #{e.message}"
        end
      end
    end

    protected

    def data_file(id); "#{@config.data_path}/#{id}.html" end
    def log_file(id); "#{@config.log_path}/#{id}.html" end
    def log_file_today; "#{@config.log_path}/daily/#{Time.now.strftime("%m_%d_%Y")}.html" end

    def parsed_options?
      @opts = OptionParser.new
      @opts.banner = "Usage: webdiffy [options] [SITE1 SITE2]\nCompare web pages line by line."

      @opts.on('-f', '--format [FORMAT]', [:color, :text, :html_simple, :html], "Select output format (color, text, html_simple, html)") {|format| @config.format = format}
      @opts.on('-s', '--sites file', 'Compare a list of files over time') {|file| @config.sites = YAML::load(File.open(file))['sites']}
      @opts.on('-b', '--log-blanks', 'Log blank diffs') {|file| @config.log_blanks = true}

      @opts.parse!(@args) rescue return false

      true
    end

    def arguments_valid?
      true unless @config.sites.nil? && @args.size == 0
    end
  end
end

app = WebDiffy::App.new(*ARGV)
app.run
