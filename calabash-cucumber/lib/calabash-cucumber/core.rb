require 'httpclient'
require 'calabash-cucumber/launch/simulator_helper'

module Calabash
  module Cucumber
    module Core

      DATA_PATH = File.expand_path(File.dirname(__FILE__))
      CAL_HTTP_RETRY_COUNT=3
      RETRYABLE_ERRORS = [Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT]

      def macro(txt)
        if self.respond_to? :step
          step(txt)
        else
          Then txt
        end
      end

      def query(uiquery, *args)
        map(uiquery, :query, *args)
      end

      def server_version
        JSON.parse(http(:path => 'version'))
      end

      def client_version
        Calabash::Cucumber::VERSION
      end

      def perform(*args)
        if args.length == 1
          #simple selector
          hash = args.first
          q = hash[:on]
          hash = hash.dup
          hash.delete(:on)
          args = [hash]
        elsif args.length == 2
          q = args[1][:on]
          if args[0].is_a? Hash
            args = [args[0]]
          else
            args = args[0]
          end
        end
        map(q, :query_all, *args)
      end

      def query_all(uiquery, *args)
        map(uiquery, :query_all, *args)
      end

      def touch(uiquery, options={})
        options[:query] = uiquery
        views_touched = playback("touch", options)
        unless uiquery.nil?
          screenshot_and_raise "could not find view to touch: '#{uiquery}', args: #{options}" if views_touched.empty?
        end
        views_touched
      end

      def swipe(dir, options={})
        dir = dir.to_sym
        @current_rotation = @current_rotation || :down
        if @current_rotation == :left
          case dir
            when :left then
              dir = :down
            when :right then
              dir = :up
            when :up then
              dir = :left
            when :down then
              dir = :right
            else
          end
        end
        if @current_rotation == :right
          case dir
            when :left then
              dir = :up
            when :right then
              dir = :down
            when :up then
              dir = :right
            when :down then
              dir = :left
            else
          end
        end
        if @current_rotation == :up
          case dir
            when :left then
              dir = :right
            when :right then
              dir = :left
            when :up then
              dir = :down
            when :down then
              dir = :up
            else
          end
        end
        playback("swipe_#{dir}", options)
      end

      def cell_swipe(options={})
        playback("cell_swipe", options)
      end

      def scroll(uiquery, direction)
        views_touched=map(uiquery, :scroll, direction)
        screenshot_and_raise "could not find view to scroll: '#{uiquery}', args: #{direction}" if views_touched.empty?
        views_touched
      end

      def scroll_to_row(uiquery, number)
        views_touched=map(uiquery, :scrollToRow, number)
        if views_touched.empty? or views_touched.member? "<VOID>"
          screenshot_and_raise "Unable to scroll: '#{uiquery}' to: #{number}"
        end
        views_touched
      end

      def scroll_to_cell(options={:query => "tableView",
                                  :row => 0,
                                  :section => 0,
                                  :scroll_position => :top,
                                  :animate => true})
        uiquery = options[:query] || "tableView"
        row = options[:row]
        sec = options[:section]
        if row.nil? or sec.nil?
          raise "You must supply both :row and :section keys to scroll_to_cell"
        end

        args = []
        if options.has_key?(:scroll_position)
          args << options[:scroll_position]
        else
          args << "top"
        end
        if options.has_key?(:animate)
          args << options[:animate]
        end
        views_touched=map(uiquery, :scrollToRow, row.to_i, sec.to_i, *args)

        if views_touched.empty? or views_touched.member? "<VOID>"
          screenshot_and_raise "Unable to scroll: '#{uiquery}' to: #{options}"
        end
        views_touched
      end

      def pinch(in_out, options={})
        file = "pinch_in"
        if in_out.to_sym==:out
          file = "pinch_out"
        end
        playback(file, options)
      end

      #Current position of home button
      def current_rotation
        @current_rotation
      end

      def rotate(dir)
        @current_rotation = @current_rotation || :down
        rotate_cmd = nil
        case dir
          when :left then
            if @current_rotation == :down
              rotate_cmd = "left_home_down"
              @current_rotation = :right
            elsif @current_rotation == :right
              rotate_cmd = "left_home_right"
              @current_rotation = :up
            elsif @current_rotation == :left
              rotate_cmd = "left_home_left"
              @current_rotation = :down
            elsif @current_rotation == :up
              rotate_cmd = "left_home_up"
              @current_rotation = :left
            end
          when :right then
            if @current_rotation == :down
              rotate_cmd = "right_home_down"
              @current_rotation = :left
            elsif @current_rotation == :left
              rotate_cmd = "right_home_left"
              @current_rotation = :up
            elsif @current_rotation == :right
              rotate_cmd = "right_home_right"
              @current_rotation = :down
            elsif @current_rotation == :up
              rotate_cmd = "right_home_up"
              @current_rotation = :right
            end
        end

        if rotate_cmd.nil?
          screenshot_and_raise "Does not support rotating #{dir} when home button is pointing #{@current_rotation}"
        end
        playback("rotate_#{rotate_cmd}")
      end

      def background(secs)
        set_user_pref("__calabash_action", {:action => :background, :duration => secs})
      end

      def prepare_dialog_action(opts={:dialog => nil, :answer => "Ok"})
        if opts[:dialog].nil? || opts[:dialog].length < 1
          raise ":dialog must be specified as a non-empty string (used as regexp to match dialog text)"
        end
        txt = opts[:answer] || 'Ok'
        set_user_pref("__calabash_action", {:action => :dialog,
                                            :text => opts[:dialog],
                                            :answer => txt})
      end

      def move_wheel(opts={})
        q = opts[:query] || "pickerView"
        wheel = opts[:wheel] || 0
        dir = opts[:dir] || :down

        raise "Wheel index must be non negative" if wheel < 0
        raise "Only up and down supported :dir (#{dir})" unless [:up, :down].include?(dir)

        if ENV['OS'] == "ios4"
          playback "wheel_#{dir}", :query => "#{q} pickerTable index:#{wheel}"
        else
          playback "wheel_#{dir}", :query => "#{q} pickerTableView index:#{wheel}"
        end

      end

      def picker(opts={:query => "pickerView", :action => :texts})
        raise "Not implemented" unless opts[:action] == :texts

        q = opts[:query]

        check_element_exists(q)

        comps = query(q, :numberOfComponents).first
        row_counts = []
        texts = []
        comps.times do |i|
          row_counts[i] = query(q, :numberOfRowsInComponent => i).first
          texts[i] = []
        end

        row_counts.each_with_index do |row_count, comp|
          row_count.times do |i|
            #view = query(q,[{:viewForRow => 0}, {:forComponent => 0}],:accessibilityLabel).first
            spec = [{:viewForRow => i}, {:forComponent => comp}]
            view = query(q, spec).first
            if view
              txt = query(q, spec, :accessibilityLabel).first
            else
              txt = query(q, :delegate, [{:pickerView => :view},
                                         {:titleForRow => i},
                                         {:forComponent => comp}]).first
            end
            texts[comp] << txt
          end
        end
        texts
      end

      def recording_name_for(recording_name, os, device)
        if !recording_name.end_with? ".base64"
          "#{recording_name}_#{os}_#{device}.base64"
        else
          recording_name
        end
      end


      def load_recording(recording,rec_dir)
        data = nil
        if (File.exists?(recording))
          data = File.read(recording)
        elsif (File.exists?("features/#{recording}"))
          data = File.read("features/#{recording}")
        elsif (File.exists?("#{rec_dir}/#{recording}"))
          data = File.read("#{rec_dir}/#{recording}")
        elsif (File.exists?("#{DATA_PATH}/resources/#{recording}"))
          data = File.read("#{DATA_PATH}/resources/#{recording}")
        end
        data
      end

      def load_playback_data(recording_name, options={})
        os = options["OS"] || ENV["OS"]
        device = options["DEVICE"] || ENV["DEVICE"] || "iphone"

        unless os
          major = Calabash::Cucumber::SimulatorHelper.ios_major_version
          unless major
            raise <<EOF
          Unable to determine iOS major version
          Most likely you have updated your calabash-cucumber client
          but not your server. Please follow closely:

https://github.com/calabash/calabash-ios/wiki/B1-Updating-your-Calabash-iOS-version

          If you are running version 0.9.120+ then please report this message as a bug.
EOF
          end
          os = "ios#{major}"
        end

        rec_dir = ENV['PLAYBACK_DIR'] || "#{Dir.pwd}/playback"

        recording = recording_name_for(recording_name, os, device)
        data = load_recording(recording,rec_dir)

        if data.nil? and os=="ios6"
          recording = recording_name_for(recording_name, "ios5", device)
        end

        data = load_recording(recording,rec_dir)

        if data.nil?
          screenshot_and_raise "Playback not found: #{recording} (searched for #{recording} in #{Dir.pwd}, #{rec_dir}, #{DATA_PATH}/resources"
        end

        data
      end

      def playback(recording, options={})
        data = load_playback_data(recording)

        post_data = %Q|{"events":"#{data}"|
        post_data<< %Q|,"query":"#{escape_quotes(options[:query])}"| if options[:query]
        post_data<< %Q|,"offset":#{options[:offset].to_json}| if options[:offset]
        post_data<< %Q|,"reverse":#{options[:reverse]}| if options[:reverse]
        post_data<< %Q|,"prototype":"#{options[:prototype]}"| if options[:prototype]
        post_data << "}"

        res = http({:method => :post, :raw => true, :path => 'play'}, post_data)

        res = JSON.parse(res)
        if res['outcome'] != 'SUCCESS'
          screenshot_and_raise "playback failed because: #{res['reason']}\n#{res['details']}"
        end
        res['results']
      end

      def interpolate(recording, options={})
        data = load_playback_data(recording)

        post_data = %Q|{"events":"#{data}"|
        post_data<< %Q|,"start":"#{escape_quotes(options[:start])}"| if options[:start]
        post_data<< %Q|,"end":"#{escape_quotes(options[:end])}"| if options[:end]
        post_data<< %Q|,"offset_start":#{options[:offset_start].to_json}| if options[:offset_start]
        post_data<< %Q|,"offset_end":#{options[:offset_end].to_json}| if options[:offset_end]
        post_data << "}"

        res = http({:method => :post, :raw => true, :path => 'interpolate'}, post_data)

        res = JSON.parse(res)
        if res['outcome'] != 'SUCCESS'
          screenshot_and_raise "interpolate failed because: #{res['reason']}\n#{res['details']}"
        end
        res['results']
      end

      def record_begin
        http({:method => :post, :path => 'record'}, {:action => :start})
      end

      def record_end(file_name)
        res = http({:method => :post, :path => 'record'}, {:action => :stop})
        File.open("_recording.plist", 'wb') do |f|
          f.write res
        end

        device = ENV['DEVICE'] || 'iphone'
        os = ENV['OS']

        unless os
          major = Calabash::Cucumber::SimulatorHelper.ios_major_version
          unless major
            raise <<EOF
          Unable to determine iOS major version
          Most likely you have updated your calabash-cucumber client
          but not your server. Please follow closely:

https://github.com/calabash/calabash-ios/wiki/B1-Updating-your-Calabash-iOS-version

          If you are running version 0.9.120+ then please report this message as a bug.
EOF
          end
          os = "ios#{major}"
        end

        file_name = "#{file_name}_#{os}_#{device}.base64"
        system("/usr/bin/plutil -convert binary1 -o _recording_binary.plist _recording.plist")
        system("openssl base64 -in _recording_binary.plist -out #{file_name}")
        system("rm _recording.plist _recording_binary.plist")
        file_name
      end

      def backdoor(sel, arg)
        json = {
            :selector => sel,
            :arg => arg
        }
        res = http({:method => :post, :path => 'backdoor'}, json)
        res = JSON.parse(res)
        if res['outcome'] != 'SUCCESS'
          screenshot_and_raise "backdoor #{json} failed because: #{res['reason']}\n#{res['details']}"
        end
        res['result']
      end

      def calabash_exit
        # Exiting the app shuts down the HTTP connection and generates ECONNREFUSED,
        # which needs to be suppressed.
        begin
          http(:path => 'exit', :retryable_errors => RETRYABLE_ERRORS - [Errno::ECONNREFUSED])
        rescue Errno::ECONNREFUSED
          []
        end
      end

      def map(query, method_name, *method_args)
        operation_map = {
            :method_name => method_name,
            :arguments => method_args
        }
        res = http({:method => :post, :path => 'map'},
                   {:query => query, :selector_engine => "calabash_uispec",
                    :operation => operation_map})
        res = JSON.parse(res)
        if res['outcome'] != 'SUCCESS'
          screenshot_and_raise "map #{query}, #{method_name} failed because: #{res['reason']}\n#{res['details']}"
        end

        res['results']
      end


      def start_app_in_background(path=nil, sdk = nil, version = 'iphone', args = nil)

        if path.nil?
          path = ENV['APP_BUNDLE_PATH'] || (defined?(APP_BUNDLE_PATH) && APP_BUNDLE_PATH)
        end
        app_bundle_path = Calabash::Cucumber::SimulatorHelper.app_bundle_or_raise(path)

        @ios_device  = RunLoop.run(:app => app_bundle_path)
      end

      def send_uia_command(opts ={})
        RunLoop.send_command(opts[:device] ||@ios_device, opts[:command])
      end

      def stop_background_app(stop_spec = nil)

        @ios_device = RunLoop.stop(stop_spec || @ios_device)

      end



      def http(options, data=nil)
        options[:uri] = url_for(options[:path])
        options[:method] = options[:method] || :get
        if data
          if options[:raw]
            options[:body] = data
          else
            options[:body] = data.to_json
          end
        end
        res = make_http_request(options)
        res.force_encoding("UTF-8") if res.respond_to?(:force_encoding)
        res
      end


      def url_for(verb)
        url = URI.parse(ENV['DEVICE_ENDPOINT']|| "http://localhost:37265")
        path = url.path
        if path.end_with? "/"
          path = "#{path}#{verb}"
        else
          path = "#{path}/#{verb}"
        end
        url.path = path
        url
      end

      def make_http_request(options)
        body = nil
        retryable_errors = options[:retryable_errors] || RETRYABLE_ERRORS
        CAL_HTTP_RETRY_COUNT.times do |count|
          begin
            if not @http
              @http = init_request(options)
            end
            if options[:method] == :post
              body = @http.post(options[:uri], options[:body]).body
            else
              body = @http.get(options[:uri], options[:body]).body
            end
            break
          rescue HTTPClient::TimeoutError, HTTPClient::KeepAliveDisconnected => e
            if count < CAL_HTTP_RETRY_COUNT-1
              sleep(0.5)
              @http.reset_all
              @http=nil
              STDOUT.write "Retrying.. #{e.class}: (#{e})\n"
              STDOUT.flush

            else
              puts "Failing... #{e.class}"
              raise e
            end

          rescue Exception => e
            if retryable_errors.include?(e)
              if count < CAL_HTTP_RETRY_COUNT-1
                sleep(0.5)
                @http.reset_all
                @http=nil
                STDOUT.write "Retrying.. #{e.class}: (#{e})\n"
                STDOUT.flush

              else
                puts "Failing... #{e.class}"
                raise e
              end
            else
              raise e
            end
          end
        end

        body
      end

      def init_request(url)
        http = HTTPClient.new
        http.connect_timeout = 15
        http.send_timeout = 15
        http.receive_timeout = 15
        http
      end
    end
  end
end
