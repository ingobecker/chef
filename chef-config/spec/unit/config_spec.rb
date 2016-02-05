#
# Author:: Adam Jacob (<adam@chef.io>)
# Author:: Kyle Goodwin (<kgoodwin@primerevenue.com>)
# Copyright:: Copyright 2008-2016, Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "spec_helper"
require "chef-config/config"

RSpec.describe ChefConfig::Config do
  before(:each) do
    ChefConfig::Config.reset

    # By default, treat deprecation warnings as errors in tests.
    ChefConfig::Config.treat_deprecation_warnings_as_errors(true)

    # Set environment variable so the setting persists in child processes
    ENV["CHEF_TREAT_DEPRECATION_WARNINGS_AS_ERRORS"] = "1"
  end

  describe "config attribute writer: chef_server_url" do
    before do
      ChefConfig::Config.chef_server_url = "https://junglist.gen.nz"
    end

    it "sets the server url" do
      expect(ChefConfig::Config.chef_server_url).to eq("https://junglist.gen.nz")
    end

    context "when the url has a leading space" do
      before do
        ChefConfig::Config.chef_server_url = " https://junglist.gen.nz"
      end

      it "strips the space from the url when setting" do
        expect(ChefConfig::Config.chef_server_url).to eq("https://junglist.gen.nz")
      end

    end

    context "when the url is a frozen string" do
      before do
        ChefConfig::Config.chef_server_url = " https://junglist.gen.nz".freeze
      end

      it "strips the space from the url when setting without raising an error" do
        expect(ChefConfig::Config.chef_server_url).to eq("https://junglist.gen.nz")
      end
    end

    context "when the url is invalid" do
      it "raises an exception" do
        expect { ChefConfig::Config.chef_server_url = "127.0.0.1" }.to raise_error(ChefConfig::ConfigurationError)
      end
    end
  end

  describe "when configuring formatters" do
      # if TTY and not(force-logger)
      #   formatter = configured formatter or default formatter
      #   formatter goes to STDOUT/ERR
      #   if log file is writeable
      #     log level is configured level or info
      #     log location is file
      #   else
      #     log level is warn
      #     log location is STDERR
      #    end
      # elsif not(TTY) and force formatter
      #   formatter = configured formatter or default formatter
      #   if log_location specified
      #     formatter goes to log_location
      #   else
      #     formatter goes to STDOUT/ERR
      #   end
      # else
      #   formatter = "null"
      #   log_location = configured-value or defualt
      #   log_level = info or defualt
      # end
      #
    it "has an empty list of formatters by default" do
      expect(ChefConfig::Config.formatters).to eq([])
    end

    it "configures a formatter with a short name" do
      ChefConfig::Config.add_formatter(:doc)
      expect(ChefConfig::Config.formatters).to eq([[:doc, nil]])
    end

    it "configures a formatter with a file output" do
      ChefConfig::Config.add_formatter(:doc, "/var/log/formatter.log")
      expect(ChefConfig::Config.formatters).to eq([[:doc, "/var/log/formatter.log"]])
    end

  end

  [ false, true ].each do |is_windows|

    context "On #{is_windows ? 'Windows' : 'Unix'}" do
      def to_platform(*args)
        ChefConfig::Config.platform_specific_path(*args)
      end

      before :each do
        allow(ChefConfig).to receive(:windows?).and_return(is_windows)
      end

      describe "class method: platform_specific_path" do
        if is_windows
          it "should return a windows path on windows systems" do
            path = "/etc/chef/cookbooks"
            allow(ChefConfig::Config).to receive(:env).and_return({ "SYSTEMDRIVE" => "C:" })
            # match on a regex that looks for the base path with an optional
            # system drive at the beginning (c:)
            # system drive is not hardcoded b/c it can change and b/c it is not present on linux systems
            expect(ChefConfig::Config.platform_specific_path(path)).to eq("C:\\chef\\cookbooks")
          end
        else
          it "should return given path on non-windows systems" do
            path = "/etc/chef/cookbooks"
            expect(ChefConfig::Config.platform_specific_path(path)).to eq("/etc/chef/cookbooks")
          end
        end
      end

      describe "default values" do
        let :primary_cache_path do
          if is_windows
            "#{ChefConfig::Config.env['SYSTEMDRIVE']}\\chef"
          else
            "/var/chef"
          end
        end

        let :secondary_cache_path do
          if is_windows
            "#{ChefConfig::Config[:user_home]}\\.chef"
          else
            "#{ChefConfig::Config[:user_home]}/.chef"
          end
        end

        before do
          if is_windows
            allow(ChefConfig::Config).to receive(:env).and_return({ "SYSTEMDRIVE" => "C:" })
            ChefConfig::Config[:user_home] = 'C:\Users\charlie'
          else
            ChefConfig::Config[:user_home] = "/Users/charlie"
          end

          allow(ChefConfig::Config).to receive(:path_accessible?).and_return(false)
        end

        describe "ChefConfig::Config[:chef_server_root]" do
          context "when chef_server_url isn't set manually" do
            it "returns the default of 'https://localhost:443'" do
              expect(ChefConfig::Config[:chef_server_root]).to eq("https://localhost:443")
            end
          end

          context "when chef_server_url matches '../organizations/*' without a trailing slash" do
            before do
              ChefConfig::Config[:chef_server_url] = "https://example.com/organizations/myorg"
            end
            it "returns the full URL without /organizations/*" do
              expect(ChefConfig::Config[:chef_server_root]).to eq("https://example.com")
            end
          end

          context "when chef_server_url matches '../organizations/*' with a trailing slash" do
            before do
              ChefConfig::Config[:chef_server_url] = "https://example.com/organizations/myorg/"
            end
            it "returns the full URL without /organizations/*" do
              expect(ChefConfig::Config[:chef_server_root]).to eq("https://example.com")
            end
          end

          context "when chef_server_url matches '..organizations..' but not '../organizations/*'" do
            before do
              ChefConfig::Config[:chef_server_url] = "https://organizations.com/organizations"
            end
            it "returns the full URL without any modifications" do
              expect(ChefConfig::Config[:chef_server_root]).to eq(ChefConfig::Config[:chef_server_url])
            end
          end

          context "when chef_server_url is a standard URL without the string organization(s)" do
            before do
              ChefConfig::Config[:chef_server_url] = "https://example.com/some_other_string"
            end
            it "returns the full URL without any modifications" do
              expect(ChefConfig::Config[:chef_server_root]).to eq(ChefConfig::Config[:chef_server_url])
            end
          end
        end

        describe "ChefConfig::Config[:cache_path]" do
          context "when /var/chef exists and is accessible" do
            it "defaults to /var/chef" do
              allow(ChefConfig::Config).to receive(:path_accessible?).with(to_platform("/var/chef")).and_return(true)
              expect(ChefConfig::Config[:cache_path]).to eq(primary_cache_path)
            end
          end

          context "when /var/chef does not exist and /var is accessible" do
            it "defaults to /var/chef" do
              allow(File).to receive(:exists?).with(to_platform("/var/chef")).and_return(false)
              allow(ChefConfig::Config).to receive(:path_accessible?).with(to_platform("/var")).and_return(true)
              expect(ChefConfig::Config[:cache_path]).to eq(primary_cache_path)
            end
          end

          context "when /var/chef does not exist and /var is not accessible" do
            it "defaults to $HOME/.chef" do
              allow(File).to receive(:exists?).with(to_platform("/var/chef")).and_return(false)
              allow(ChefConfig::Config).to receive(:path_accessible?).with(to_platform("/var")).and_return(false)
              expect(ChefConfig::Config[:cache_path]).to eq(secondary_cache_path)
            end
          end

          context "when /var/chef exists and is not accessible" do
            it "defaults to $HOME/.chef" do
              allow(File).to receive(:exists?).with(to_platform("/var/chef")).and_return(true)
              allow(File).to receive(:readable?).with(to_platform("/var/chef")).and_return(true)
              allow(File).to receive(:writable?).with(to_platform("/var/chef")).and_return(false)

              expect(ChefConfig::Config[:cache_path]).to eq(secondary_cache_path)
            end
          end

          context "when chef is running in local mode" do
            before do
              ChefConfig::Config.local_mode = true
            end

            context "and config_dir is /a/b/c" do
              before do
                ChefConfig::Config.config_dir to_platform("/a/b/c")
              end

              it "cache_path is /a/b/c/local-mode-cache" do
                expect(ChefConfig::Config.cache_path).to eq(to_platform("/a/b/c/local-mode-cache"))
              end
            end

            context "and config_dir is /a/b/c/" do
              before do
                ChefConfig::Config.config_dir to_platform("/a/b/c/")
              end

              it "cache_path is /a/b/c/local-mode-cache" do
                expect(ChefConfig::Config.cache_path).to eq(to_platform("/a/b/c/local-mode-cache"))
              end
            end
          end
        end

        it "ChefConfig::Config[:stream_execute_output] defaults to false" do
          expect(ChefConfig::Config[:stream_execute_output]).to eq(false)
        end

        it "ChefConfig::Config[:file_backup_path] defaults to /var/chef/backup" do
          allow(ChefConfig::Config).to receive(:cache_path).and_return(primary_cache_path)
          backup_path = is_windows ? "#{primary_cache_path}\\backup" : "#{primary_cache_path}/backup"
          expect(ChefConfig::Config[:file_backup_path]).to eq(backup_path)
        end

        it "ChefConfig::Config[:ssl_verify_mode] defaults to :verify_peer" do
          expect(ChefConfig::Config[:ssl_verify_mode]).to eq(:verify_peer)
        end

        it "ChefConfig::Config[:ssl_ca_path] defaults to nil" do
          expect(ChefConfig::Config[:ssl_ca_path]).to be_nil
        end

        describe "ChefConfig::Config[:repo_mode]" do

          context "when local mode is enabled" do

            before { ChefConfig::Config[:local_mode] = true }

            it "defaults to 'hosted_everything'" do
              expect(ChefConfig::Config[:repo_mode]).to eq("hosted_everything")
            end

            context "and osc_compat is enabled" do

              before { ChefConfig::Config.chef_zero.osc_compat = true }

              it "defaults to 'everything'" do
                expect(ChefConfig::Config[:repo_mode]).to eq("everything")
              end
            end
          end

          context "when local mode is not enabled" do

            context "and the chef_server_url is multi-tenant" do

              before { ChefConfig::Config[:chef_server_url] = "https://chef.example/organizations/example" }

              it "defaults to 'hosted_everything'" do
                expect(ChefConfig::Config[:repo_mode]).to eq("hosted_everything")
              end

            end

            context "and the chef_server_url is not multi-tenant" do

              before { ChefConfig::Config[:chef_server_url] = "https://chef.example/" }

              it "defaults to 'everything'" do
                expect(ChefConfig::Config[:repo_mode]).to eq("everything")
              end
            end
          end
        end

        describe "ChefConfig::Config[:chef_repo_path]" do

          context "when cookbook_path is set to a single path" do

            before { ChefConfig::Config[:cookbook_path] = "/home/anne/repo/cookbooks" }

            it "is set to a path one directory up from the cookbook_path" do
              expected = File.expand_path("/home/anne/repo")
              expect(ChefConfig::Config[:chef_repo_path]).to eq(expected)
            end

          end

          context "when cookbook_path is set to multiple paths" do

            before do
              ChefConfig::Config[:cookbook_path] = [
                "/home/anne/repo/cookbooks",
                "/home/anne/other_repo/cookbooks",
              ]
            end

            it "is set to an Array of paths one directory up from the cookbook_paths" do
              expected = [ "/home/anne/repo", "/home/anne/other_repo"].map { |p| File.expand_path(p) }
              expect(ChefConfig::Config[:chef_repo_path]).to eq(expected)
            end

          end

          context "when cookbook_path is not set but cookbook_artifact_path is set" do

            before do
              ChefConfig::Config[:cookbook_path] = nil
              ChefConfig::Config[:cookbook_artifact_path] = "/home/roxie/repo/cookbook_artifacts"
            end

            it "is set to a path one directory up from the cookbook_artifact_path" do
              expected = File.expand_path("/home/roxie/repo")
              expect(ChefConfig::Config[:chef_repo_path]).to eq(expected)
            end

          end

          context "when cookbook_path is not set" do

            before { ChefConfig::Config[:cookbook_path] = nil }

            it "is set to the cache_path" do
              expect(ChefConfig::Config[:chef_repo_path]).to eq(ChefConfig::Config[:cache_path])
            end

          end

        end

        # On Windows, we'll detect an omnibus build and set this to the
        # cacert.pem included in the package, but it's nil if you're on Windows
        # w/o omnibus (e.g., doing development on Windows, custom build, etc.)
        if !is_windows
          it "ChefConfig::Config[:ssl_ca_file] defaults to nil" do
            expect(ChefConfig::Config[:ssl_ca_file]).to be_nil
          end
        end

        it "ChefConfig::Config[:data_bag_path] defaults to /var/chef/data_bags" do
          allow(ChefConfig::Config).to receive(:cache_path).and_return(primary_cache_path)
          data_bag_path = is_windows ? "#{primary_cache_path}\\data_bags" : "#{primary_cache_path}/data_bags"
          expect(ChefConfig::Config[:data_bag_path]).to eq(data_bag_path)
        end

        it "ChefConfig::Config[:environment_path] defaults to /var/chef/environments" do
          allow(ChefConfig::Config).to receive(:cache_path).and_return(primary_cache_path)
          environment_path = is_windows ? "#{primary_cache_path}\\environments" : "#{primary_cache_path}/environments"
          expect(ChefConfig::Config[:environment_path]).to eq(environment_path)
        end

        it "ChefConfig::Config[:cookbook_artifact_path] defaults to /var/chef/cookbook_artifacts" do
          allow(ChefConfig::Config).to receive(:cache_path).and_return(primary_cache_path)
          environment_path = is_windows ? "#{primary_cache_path}\\cookbook_artifacts" : "#{primary_cache_path}/cookbook_artifacts"
          expect(ChefConfig::Config[:cookbook_artifact_path]).to eq(environment_path)
        end

        describe "setting the config dir" do

          context "when the config file is given with a relative path" do

            before do
              ChefConfig::Config.config_file = "client.rb"
            end

            it "expands the path when determining config_dir" do
              # config_dir goes through PathHelper.canonical_path, which
              # downcases on windows because the FS is case insensitive, so we
              # have to downcase expected and actual to make the tests work.
              expect(ChefConfig::Config.config_dir.downcase).to eq(to_platform(Dir.pwd).downcase)
            end

            it "does not set derived paths at FS root" do
              ChefConfig::Config.local_mode = true
              expect(ChefConfig::Config.cache_path.downcase).to eq(to_platform(File.join(Dir.pwd, "local-mode-cache")).downcase)
            end

          end

          context "when the config file is /etc/chef/client.rb" do

            before do
              config_location = to_platform("/etc/chef/client.rb").downcase
              allow(File).to receive(:absolute_path).with(config_location).and_return(config_location)
              ChefConfig::Config.config_file = config_location
            end

            it "config_dir is /etc/chef" do
              expect(ChefConfig::Config.config_dir).to eq(to_platform("/etc/chef").downcase)
            end

            context "and chef is running in local mode" do
              before do
                ChefConfig::Config.local_mode = true
              end

              it "config_dir is /etc/chef" do
                expect(ChefConfig::Config.config_dir).to eq(to_platform("/etc/chef").downcase)
              end
            end

            context "when config_dir is set to /other/config/dir/" do
              before do
                ChefConfig::Config.config_dir = to_platform("/other/config/dir/")
              end

              it "yields the explicit value" do
                expect(ChefConfig::Config.config_dir).to eq(to_platform("/other/config/dir/"))
              end
            end

          end

          context "when the user's home dir is /home/charlie/" do
            before do
              ChefConfig::Config.user_home = to_platform("/home/charlie")
            end

            it "config_dir is /home/charlie/.chef/" do
              expect(ChefConfig::Config.config_dir).to eq(ChefConfig::PathHelper.join(to_platform("/home/charlie/.chef"), ""))
            end

            context "and chef is running in local mode" do
              before do
                ChefConfig::Config.local_mode = true
              end

              it "config_dir is /home/charlie/.chef/" do
                expect(ChefConfig::Config.config_dir).to eq(ChefConfig::PathHelper.join(to_platform("/home/charlie/.chef"), ""))
              end
            end
          end

        end

        if is_windows
          describe "finding the windows embedded dir" do
            let(:default_config_location) { "c:/opscode/chef/embedded/lib/ruby/gems/1.9.1/gems/chef-11.6.0/lib/chef/config.rb" }
            let(:alternate_install_location) { "c:/my/alternate/install/place/chef/embedded/lib/ruby/gems/1.9.1/gems/chef-11.6.0/lib/chef/config.rb" }
            let(:non_omnibus_location) { "c:/my/dev/stuff/lib/ruby/gems/1.9.1/gems/chef-11.6.0/lib/chef/config.rb" }

            let(:default_ca_file) { "c:/opscode/chef/embedded/ssl/certs/cacert.pem" }

            it "finds the embedded dir in the default location" do
              allow(ChefConfig::Config).to receive(:_this_file).and_return(default_config_location)
              expect(ChefConfig::Config.embedded_dir).to eq("c:/opscode/chef/embedded")
            end

            it "finds the embedded dir in a custom install location" do
              allow(ChefConfig::Config).to receive(:_this_file).and_return(alternate_install_location)
              expect(ChefConfig::Config.embedded_dir).to eq("c:/my/alternate/install/place/chef/embedded")
            end

            it "doesn't error when not in an omnibus install" do
              allow(ChefConfig::Config).to receive(:_this_file).and_return(non_omnibus_location)
              expect(ChefConfig::Config.embedded_dir).to be_nil
            end

            it "sets the ssl_ca_cert path if the cert file is available" do
              allow(ChefConfig::Config).to receive(:_this_file).and_return(default_config_location)
              allow(File).to receive(:exist?).with(default_ca_file).and_return(true)
              expect(ChefConfig::Config.ssl_ca_file).to eq(default_ca_file)
            end
          end
        end
      end

      describe "ChefConfig::Config[:user_home]" do
        it "should set when HOME is provided" do
          expected = to_platform("/home/kitten")
          allow(ChefConfig::PathHelper).to receive(:home).and_return(expected)
          expect(ChefConfig::Config[:user_home]).to eq(expected)
        end

        it "falls back to the current working directory when HOME and USERPROFILE is not set" do
          allow(ChefConfig::PathHelper).to receive(:home).and_return(nil)
          expect(ChefConfig::Config[:user_home]).to eq(Dir.pwd)
        end
      end

      describe "ChefConfig::Config[:encrypted_data_bag_secret]" do
        let(:db_secret_default_path){ to_platform("/etc/chef/encrypted_data_bag_secret") }

        before do
          allow(File).to receive(:exist?).with(db_secret_default_path).and_return(secret_exists)
        end

        context "/etc/chef/encrypted_data_bag_secret exists" do
          let(:secret_exists) { true }
          it "sets the value to /etc/chef/encrypted_data_bag_secret" do
            expect(ChefConfig::Config[:encrypted_data_bag_secret]).to eq db_secret_default_path
          end
        end

        context "/etc/chef/encrypted_data_bag_secret does not exist" do
          let(:secret_exists) { false }
          it "sets the value to nil" do
            expect(ChefConfig::Config[:encrypted_data_bag_secret]).to be_nil
          end
        end
      end

      describe "ChefConfig::Config[:event_handlers]" do
        it "sets a event_handlers to an empty array by default" do
          expect(ChefConfig::Config[:event_handlers]).to eq([])
        end
        it "should be able to add custom handlers" do
          o = Object.new
          ChefConfig::Config[:event_handlers] << o
          expect(ChefConfig::Config[:event_handlers]).to be_include(o)
        end
      end

      describe "ChefConfig::Config[:user_valid_regex]" do
        context "on a platform that is not Windows" do
          it "allows one letter usernames" do
            any_match = ChefConfig::Config[:user_valid_regex].any? { |regex| regex.match("a") }
            expect(any_match).to be_truthy
          end
        end
      end

      describe "ChefConfig::Config[:internal_locale]" do
        let(:shell_out) do
          cmd = instance_double("Mixlib::ShellOut", exitstatus: 0, stdout: locales, error!: nil)
          allow(cmd).to receive(:run_command).and_return(cmd)
          cmd
        end

        let(:locales) { locale_array.join("\n") }

        before do
          allow(Mixlib::ShellOut).to receive(:new).with("locale -a").and_return(shell_out)
        end

        shared_examples_for "a suitable locale" do
          it "returns an English UTF-8 locale" do
            expect(ChefConfig.logger).to_not receive(:warn).with(/Please install an English UTF-8 locale for Chef to use/)
            expect(ChefConfig.logger).to_not receive(:debug).with(/Defaulting to locale en_US.UTF-8 on Windows/)
            expect(ChefConfig.logger).to_not receive(:debug).with(/No usable locale -a command found/)
            expect(ChefConfig::Config.guess_internal_locale).to eq expected_locale
          end
        end

        context "when the result includes 'C.UTF-8'" do
          include_examples "a suitable locale" do
            let(:locale_array) { [expected_locale, "en_US.UTF-8"] }
            let(:expected_locale) { "C.UTF-8" }
          end
        end

        context "when the result includes 'en_US.UTF-8'" do
          include_examples "a suitable locale" do
            let(:locale_array) { ["en_CA.UTF-8", expected_locale, "en_NZ.UTF-8"] }
            let(:expected_locale) { "en_US.UTF-8" }
          end
        end

        context "when the result includes 'en_US.utf8'" do
          include_examples "a suitable locale" do
            let(:locale_array) { ["en_CA.utf8", "en_US.utf8", "en_NZ.utf8"] }
            let(:expected_locale) { "en_US.UTF-8" }
          end
        end

        context "when the result includes 'en.UTF-8'" do
          include_examples "a suitable locale" do
            let(:locale_array) { ["en.ISO8859-1", expected_locale] }
            let(:expected_locale) { "en.UTF-8" }
          end
        end

        context "when the result includes 'en_*.UTF-8'" do
          include_examples "a suitable locale" do
            let(:locale_array) { [expected_locale, "en_CA.UTF-8", "en_GB.UTF-8"] }
            let(:expected_locale) { "en_AU.UTF-8" }
          end
        end

        context "when the result includes 'en_*.utf8'" do
          include_examples "a suitable locale" do
            let(:locale_array) { ["en_AU.utf8", "en_CA.utf8", "en_GB.utf8"] }
            let(:expected_locale) { "en_AU.UTF-8" }
          end
        end

        context "when the result does not include 'en_*.UTF-8'" do
          let(:locale_array) { ["af_ZA", "af_ZA.ISO8859-1", "af_ZA.ISO8859-15", "af_ZA.UTF-8"] }

          it "should fall back to C locale" do
            expect(ChefConfig.logger).to receive(:warn).with("Please install an English UTF-8 locale for Chef to use, falling back to C locale and disabling UTF-8 support.")
            expect(ChefConfig::Config.guess_internal_locale).to eq "C"
          end
        end

        context "on error" do
          let(:locale_array) { [] }

          let(:shell_out_cmd) { instance_double("Mixlib::ShellOut") }

          before do
            allow(Mixlib::ShellOut).to receive(:new).and_return(shell_out_cmd)
            allow(shell_out_cmd).to receive(:run_command)
            allow(shell_out_cmd).to receive(:error!).and_raise(Mixlib::ShellOut::ShellCommandFailed, "this is an error")
          end

          it "should default to 'en_US.UTF-8'" do
            if is_windows
              expect(ChefConfig.logger).to receive(:debug).with("Defaulting to locale en_US.UTF-8 on Windows, until it matters that we do something else.")
            else
              expect(ChefConfig.logger).to receive(:debug).with("No usable locale -a command found, assuming you have en_US.UTF-8 installed.")
            end
            expect(ChefConfig::Config.guess_internal_locale).to eq "en_US.UTF-8"
          end
        end
      end
    end
  end

  describe "export_proxies" do
    let(:http_proxy) { "http://localhost:7979" }
    let(:https_proxy) { "https://localhost:7979" }
    let(:ftp_proxy) { "ftp://localhost:7979" }
    let(:proxy_user) { "http_user" }
    let(:proxy_pass) { "http_pass" }

    context "when http_proxy, proxy_pass and proxy_user are set" do
      before do
        ChefConfig::Config.http_proxy = http_proxy
        ChefConfig::Config.http_proxy_user = proxy_user
        ChefConfig::Config.http_proxy_pass = proxy_pass
      end
      it "exports ENV['http_proxy']" do
        expect(ENV).to receive(:[]=).with("http_proxy", "http://http_user:http_pass@localhost:7979")
        expect(ENV).to receive(:[]=).with("HTTP_PROXY", "http://http_user:http_pass@localhost:7979")
        ChefConfig::Config.export_proxies
      end
    end

    context "when https_proxy, proxy_pass and proxy_user are set" do
      before do
        ChefConfig::Config.https_proxy = https_proxy
        ChefConfig::Config.https_proxy_user = proxy_user
        ChefConfig::Config.https_proxy_pass = proxy_pass
      end
      it "exports ENV['https_proxy']" do
        expect(ENV).to receive(:[]=).with("https_proxy", "https://http_user:http_pass@localhost:7979")
        expect(ENV).to receive(:[]=).with("HTTPS_PROXY", "https://http_user:http_pass@localhost:7979")
        ChefConfig::Config.export_proxies
      end
    end

    context "when ftp_proxy, proxy_pass and proxy_user are set" do
      before do
        ChefConfig::Config.ftp_proxy = ftp_proxy
        ChefConfig::Config.ftp_proxy_user = proxy_user
        ChefConfig::Config.ftp_proxy_pass = proxy_pass
      end
      it "exports ENV['ftp_proxy']" do
        expect(ENV).to receive(:[]=).with("ftp_proxy", "ftp://http_user:http_pass@localhost:7979")
        expect(ENV).to receive(:[]=).with("FTP_PROXY", "ftp://http_user:http_pass@localhost:7979")
        ChefConfig::Config.export_proxies
      end
    end

    shared_examples "no user pass" do
      it "does not populate the user or password" do
        expect(ENV).to receive(:[]=).with("http_proxy", "http://localhost:7979")
        expect(ENV).to receive(:[]=).with("HTTP_PROXY", "http://localhost:7979")
        ChefConfig::Config.export_proxies
      end
    end

    context "when proxy_pass and proxy_user are passed as empty strings" do
      before do
        ChefConfig::Config.http_proxy = http_proxy
        ChefConfig::Config.http_proxy_user = ""
        ChefConfig::Config.http_proxy_pass = proxy_pass
      end
      include_examples "no user pass"
    end

    context "when proxy_pass and proxy_user are not provided" do
      before do
        ChefConfig::Config.http_proxy = http_proxy
      end
      include_examples "no user pass"
    end

    context "when the proxy is provided without a scheme" do
      before do
        ChefConfig::Config.http_proxy = "localhost:1111"
      end
      it "automatically adds the scheme to the proxy url" do
        expect(ENV).to receive(:[]=).with("http_proxy", "http://localhost:1111")
        expect(ENV).to receive(:[]=).with("HTTP_PROXY", "http://localhost:1111")
        ChefConfig::Config.export_proxies
      end
    end

    shared_examples "no export" do
      it "does not export any proxy settings" do
        ChefConfig::Config.export_proxies
        expect(ENV["http_proxy"]).to eq(nil)
        expect(ENV["https_proxy"]).to eq(nil)
        expect(ENV["ftp_proxy"]).to eq(nil)
        expect(ENV["no_proxy"]).to eq(nil)
      end
    end

    context "when nothing is set" do
      include_examples "no export"
    end

    context "when all the users and passwords are set but no proxies are set" do
      before do
        ChefConfig::Config.http_proxy_user = proxy_user
        ChefConfig::Config.http_proxy_pass = proxy_pass
        ChefConfig::Config.https_proxy_user = proxy_user
        ChefConfig::Config.https_proxy_pass = proxy_pass
        ChefConfig::Config.ftp_proxy_user = proxy_user
        ChefConfig::Config.ftp_proxy_pass = proxy_pass
      end
      include_examples "no export"
    end

    context "no_proxy is set" do
      before do
        ChefConfig::Config.no_proxy = "localhost"
      end
      it "exports ENV['no_proxy']" do
        expect(ENV).to receive(:[]=).with("no_proxy", "localhost")
        expect(ENV).to receive(:[]=).with("NO_PROXY", "localhost")
        ChefConfig::Config.export_proxies
      end
    end
  end

  describe "allowing chefdk configuration outside of chefdk" do

    it "allows arbitrary settings in the chefdk config context" do
      expect { ChefConfig::Config.chefdk.generator_cookbook("/path") }.to_not raise_error
    end

  end

  describe "Treating deprecation warnings as errors" do

    context "when using our default RSpec configuration" do

      it "defaults to treating deprecation warnings as errors" do
        expect(ChefConfig::Config[:treat_deprecation_warnings_as_errors]).to be(true)
      end

      it "sets CHEF_TREAT_DEPRECATION_WARNINGS_AS_ERRORS environment variable" do
        expect(ENV["CHEF_TREAT_DEPRECATION_WARNINGS_AS_ERRORS"]).to eq("1")
      end

      it "treats deprecation warnings as errors in child processes when testing" do
        # Doing a full integration test where we launch a child process is slow
        # and liable to break for weird reasons (bundler env stuff, etc.), so
        # we're just checking that the presence of the environment variable
        # causes treat_deprecation_warnings_as_errors to be set to true after a
        # config reset.
        ChefConfig::Config.reset
        expect(ChefConfig::Config[:treat_deprecation_warnings_as_errors]).to be(true)
      end

    end

    context "outside of our test environment" do

      before do
        ENV.delete("CHEF_TREAT_DEPRECATION_WARNINGS_AS_ERRORS")
        ChefConfig::Config.reset
      end

      it "defaults to NOT treating deprecation warnings as errors" do
        expect(ChefConfig::Config[:treat_deprecation_warnings_as_errors]).to be(false)
      end
    end


  end

end