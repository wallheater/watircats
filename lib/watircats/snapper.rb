require 'watir-webdriver'

module WatirCats
  class Snapper
    
    BROWSER_HEIGHT = 5000

    def initialize(base_url, scheme, site_map)
      puts "Snapper host: #{base_url}"
      @base_url       = base_url # (actually just the HOSTNAME)
      @scheme         = scheme
      @screenshot_dir = WatirCats.config.screenshot_dir
      @widths         = WatirCats.config.widths
      @images_dir     = WatirCats.config.images_dir
      @delay          = WatirCats.config.delay
      # Handle the environments that require profile configuration
      configure_browser

      # Allowing for custom page class tests
      @class_tests          = [ ]
      @class_test_mapping   = { }
      @@custom_test_results = { }

      # Retrieve the paths from the sitemap
      @paths      = site_map.the_paths
      @time_stamp = Time.now.to_i.to_s

      process_paths
      @browser.quit
    end

    def resize_browser(width)
      # Set a max height using the constant BROWSER_HEIGHT
      @browser.window.resize_to(width, BROWSER_HEIGHT)
    end

    def capture_page_image(url, file_name)
      
      # skip existing screenshots if we've specified that option
      if WatirCats.config.skip_existing
        if FileTest.exists?(file_name)
         puts "Skipping existing file at " + file_name # verbose
         return
        end
      end

      print "goto: #{url}" # verbose, no lf
      begin
        @browser.goto url
        # Wait for page to complete loading by querying document.readyState
        script = "return document.readyState"
        @browser.wait_until { @browser.execute_script(script) == "complete" }
      rescue => e
        puts "" # lf
        puts "  oops! tried goto & wait_until but: #{e}"
        # puts "  browser status: " + @browser.status # crashes!
        # fingers crossed!
        @browser.close
        configure_browser
        return
      end
      
      if @browser.url != url
        # @todo detect if host is different, offsite redirect
        puts "" # lf
        puts "  redirected to: #{@browser.url}" # verbose
      else
        puts " - OK"
      end

      # Skip if a redirect matches the avoided path
      if WatirCats.config.avoided_path
        if @browser.url.match( /#{WatirCats.config.avoided_path}/ )
          puts "  skipped, redirect matches: /#{WatirCats.config.avoided_path}/" # verbose
          return
        end
      end

      # quick and dirty page delay for issue #1
      if @delay
        @browser.wait_until { sleep(@delay) }
      end

      # Take and save the screenshot      
      @browser.screenshot.save(file_name)
    end

    def widths
      @widths = @widths || [1024]
    end

    def self.folders
      # Class variable, to keep track of folders amongst all instances of this class
      @@folders ||= []
    end

    def add_folder(folder)
      @@folders ||= [] # Ensure @@folders exists
      @@folders << folder
    end

    def process_paths
      # Build the unique directory unless it exists
      FileUtils.mkdir "#{@screenshot_dir}" unless File.directory? "#{@screenshot_dir}"

      stamped_base_url_folder = "#{@screenshot_dir}/#{@base_url}-#{@time_stamp}"
      if @images_dir
          stamped_base_url_folder = "#{@screenshot_dir}/#{@images_dir}"
      end
	
      FileUtils.mkdir "#{stamped_base_url_folder}" unless File.directory? "#{stamped_base_url_folder}"
 
      add_folder(stamped_base_url_folder)

      # Some setup for processing
      paths = @paths
      widths = self.widths

      # Iterate through the paths, using the key as a label, value as a path
      paths.each do |label, path|

        # @TODO wait a minute, why are we looking at @browser.body here when we haven't used path at all yet!?!?
        # if @browser.body.exists?
        if false
          # Create our base array to use to execute tests
          potential_body_classes = [:all]
          # Do custom tests here
          # @TODO next line crashes after timeout e.g. http://col-forestlake-k12-mn0.dev.clockwork.net/ql_quick_links/ql_lunches/
          body_classes = @browser.body.class_name
          # Split the class string for the <body> element on spaces, then shovel
          # each body_class into the potential_body_classes array
          body_classes.split.each { |body_class| potential_body_classes << body_class }

          @@custom_test_results[path] = {}

          potential_body_classes.each do |the_class|
            if @class_tests.include? the_class
              methods_to_send = @class_test_mapping[the_class]

              methods_to_send.each do |custom_method|
                @@custom_test_results[path][custom_method] = self.send( custom_method )
              end

            end
          end
        end
        # end body dependency

        # Skip if a redirect matches the avoided path
        # @TODO this seems to be in the wrong place; no url has been goto'ed here
        # or path instead of @browser.url?
        if WatirCats.config.avoided_path
          if path.match( /#{WatirCats.config.avoided_path}/ )
            puts "skipping avoided path (in process_paths): #{path}" # verbose
            next
          end
        end
        # For each width, resize the browser, take a screenshot
        widths.each do |width|
          resize_browser width
          file_name = "#{stamped_base_url_folder}/#{label}_#{width}.png"
          capture_page_image("#{@scheme}://#{@base_url}#{path}", file_name)
        end
      end
    end

    def configure_browser
      engine = WatirCats.config.browser || :ff

      # Firefox only stuff, allowing a custom binary location and proxy support
      if ( engine.to_sym == :ff || engine.to_sym == :firefox )

        bin_path = WatirCats.config.ff_path
        proxy    = WatirCats.config.proxy
        ::Selenium::WebDriver::Firefox::Binary.path= bin_path if bin_path.is_a? String
        
        profile = ::Selenium::WebDriver::Firefox::Profile.new 
        
        if proxy
          profile.proxy = ::Selenium::WebDriver::Proxy.new :http => proxy, :ssl => proxy
        end

        profile['app.update.auto']    = false
        profile['app.update.enabled'] = false

        @browser = ::Watir::Browser.new engine, :profile => profile
      else
        @browser = ::Watir::Browser.new engine
      end
    end

    def self.custom_test_results
      @@custom_test_results ||= { }
    end

  end
end
