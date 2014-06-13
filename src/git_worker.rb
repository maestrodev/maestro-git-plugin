# Copyright (c) 2013 MaestroDev.  All rights reserved.
require 'maestro_plugin'
require 'maestro_shell'

module MaestroDev
  module Plugin

    class GitWorker < Maestro::MaestroWorker

      def clone
        validate_clone_parameters

        # save the path for later tasks
        set_field('scm_path', @path)
        set_field('git_path', @path)

        if File.exists? @path and @clean_working_copy
          write_output("\nDeleting old path - #{@path}", :buffer => true)
          FileUtils.rm_rf @path
        end

        use_clone = true

        if File.exists? @path
          remote_url = get_remote_origin

          if remote_url
            raise PluginError, "Request for git clone of '#{@url}' into '#{@path}', but #{remote_url} already squatting the " +
              "directory.\nThis usually indicates two compositions are set to use the same directory for their checkouts.\n" +
              "Either manually remove '#{@path}' or select the 'Clean Working Copy' option (if left on this will slow down " +
              "repeated builds, increase checkout/update time, and generally reduce system efficiency)" if remote_url != @url
            use_clone = false
          end
        end

        if use_clone
          # first clone
          write_output("\nGit clone: cloning #{@url} to #{@path}\n", :buffer => true)
          clone_script = "#{@env}#{@executable} clone -v #{@url} #{@path}"
        else
          Maestro.log.debug "Git clone: repo already exists at #{@path}, pulling instead"
          write_output("\nUpdating repo - #{@url} at #{@path}\n", :buffer => true)
          clone_script = "cd #{@path} && #{@env}#{@executable} pull"
        end
        shell = Maestro::Util::Shell.new
        shell.create_script(clone_script)
        write_output("\nRunning command:\n----------\n#{clone_script.chomp}\n----------\n")
        shell.run_script_with_delegate(self, :on_output)
        raise PluginError, "Error cloning repo" unless shell.exit_code.success?

        unless !shell.exit_code.success? or @branch.empty? or @branch == "master" 
          checkout = Maestro::Util::Shell.new
          checkout_script = "cd #{@path} && #{@env}#{@executable} checkout #{@branch}"

          checkout.create_script(checkout_script)
          write_output("\nRunning command:\n----------\n#{checkout_script.chomp}\n----------\n")
          checkout.run_script_with_delegate(self, :on_output)
          raise PluginError, "Error on branch checkout" unless checkout.exit_code.success?
        end

        latest_ref = read_output_value('reference')
        local_ref = get_local_ref
        write_output("\nPrevious build used git ref: #{latest_ref}, this update is ref: #{local_ref}, force_build: #{@force_build}", :buffer => true)

        save_output_value('reference', local_ref)
        save_output_value('url', @url)
        save_output_value('branch', @branch)
        save_output_value('commit_id', local_ref)  # Same as reference, but name should be consistent with other VCS

        perpetrators = get_committer_author_info

        save_output_value('committer_email', perpetrators[:committer_email])
        save_output_value('committer_name', perpetrators[:committer_name])
        save_output_value('author_email', perpetrators[:author_email])
        save_output_value('author_name', perpetrators[:author_name])

        write_output("\ngit ref:   #{local_ref}\ncommitter: #{perpetrators[:committer_name]} (#{perpetrators[:committer_email]})\nauthor:    #{perpetrators[:author_name]} (#{perpetrators[:author_email]})", :buffer => true)

        tickets = get_tickets(latest_ref, local_ref)

        save_output_value('tickets', tickets)
        write_output("\ntickets:   #{tickets.length} (#{tickets.join(', ')})", :buffer => true) unless tickets.empty?

        if !latest_ref.nil? and !latest_ref.empty? and latest_ref == local_ref and !get_field('force_build')
          write_output "\nReference From Previous Build #{latest_ref} Equals Latest From Repo - Build Not Needed"
          not_needed
        end
      end

      def branch
        validate_branch_parameters

        write_output("\nCreating the branch: #{@branch} in the repo at #{@path}\n", :buffer => true)
        
        branch_script = "cd #{@path} && #{@env} #{@executable} branch -v #{@branch} && #{@executable} push -v #{@remote_repo} #{@branch}"
        
        shell = Maestro::Util::Shell.new
        shell.create_script(branch_script)
        write_output("\nRunning command:\n----------\n#{branch_script.chomp}\n----------\n")
        shell.run_script_with_delegate(self, :on_output)
        
        raise PluginError, "Error creating the branch" unless shell.exit_code.success?
      end
  
      def tag
        validate_tag_parameters
  
        write_output("Tagging the repo at #{@path} with tagname: #{@tag_name}", :buffer => true)
        write_output(" and commit checksum starting with #{@commit_checksum}", :buffer => true) unless @commit_checksum.empty?
        write_output(" with the tag message: '#{@message}'", :buffer => true) unless @message.empty?
        write_output(" and pushing it to the remote repository: #{@remote_repo} #{@branch}", :buffer => true)
  
        tagcommand = "tag -a #{@tag_name}"
        tagcommand += " #{@commit_checksum}" unless @commit_checksum.empty?
        tagcommand += " -m '#{@message}'" unless @message.empty?
  
        pushcommand = "push -v --tags #{@remote_repo} #{@branch}"
  
        tag_script = "cd #{@path} && #{@env} #{@executable} #{tagcommand} && #{@executable} #{pushcommand}"
  
        shell = Maestro::Util::Shell.new
        shell.create_script(tag_script)
        write_output("\nRunning command:\n----------\n#{tag_script.chomp}\n----------\n")
        shell.run_script_with_delegate(self, :on_output)
  
        raise PluginError, "Error tagging the repo" unless shell.exit_code.success?
      end
  
      def on_output(text)
        write_output(text, :buffer => true)
      end
  
      private
  
      def valid_executable?(executable)
        Maestro::Util::Shell.run_command("#{executable} --version")[0].success?
      end
  
      def default_path
        s = get_field('composition', '').downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')
        File.expand_path("~/wc/#{s}-#{get_field('composition_id', '')}")
      end
  
      def validate_common_parameters
        errors = []
  
        @executable = get_field('executable', 'git')
        @path = get_field('path') || default_path
        @environment = get_field('environment', '')
        @env = @environment.empty? ? "" : "#{Maestro::Util::Shell::ENV_EXPORT_COMMAND} #{@environment.gsub(/(&&|[;&])\s*$/, '')} && "
  
        save_output_value('repo_path', @path)
  
        errors << 'git not installed (or not on path)' if !valid_executable?(@executable)
  
        errors
      end
  
      def validate_clone_parameters
        errors = validate_common_parameters
  
        @branch = get_field('branch', 'master')
        @url = get_field('url', '')
        @clean_working_copy = get_boolean_field('clean_working_copy')
        @force_build = get_boolean_field('force_build')
  
        errors << 'no git url specified' if @url.empty?
  
        if !errors.empty?
          raise ConfigError, "Configuration errors: #{errors.join(', ')}"
        end
      end
      
      def validate_branch_parameters
        errors = validate_common_parameters
      
        @branch = get_field('branch_name', '')
        @remote_repo = get_field('remote_repo', '')
        
        errors << 'no remote_repo specified' if @remote_repo.empty?
        errors << 'no branch name specified' if @branch.empty?
      
        if !errors.empty?
          raise ConfigError, "Configuration errors: #{errors.join(', ')}"
        end
      end
  
      def validate_tag_parameters
        errors = validate_common_parameters
  
        @branch = get_field('remote_branch', '')
        @remote_repo = get_field('remote_repo', '')
        @tag_name = get_field('tag_name', '')
        @commit_checksum = get_field('commit_checksum', '')
        @message = get_field('message', '')
        
        errors << 'no tag name specified' if @tag_name.empty?
        errors << 'no remote_repo specified' if @remote_repo.empty?
  
        if !errors.empty?
          raise ConfigError, "Configuration errors: #{errors.join(', ')}"
        end
      end
  
      def get_ref(ref_path)
        show_ref = Maestro::Util::Shell.new
        show_ref.create_script("cd #{@path}; git show-ref")
        show_ref.run_script
        raise PluginError, "Error Detecting Reference: #{show_ref.output}" unless show_ref.exit_code.success?
  
        ref = show_ref.output
        mout = ref.match(/(\w+)\s#{ref_path}/)
        ref = mout && mout[1]
        ref = "Unknown Reference" unless ref.is_a? String
        write_output("\nref for '#{ref_path}' is #{ref}", :buffer => true)
        ref
      end
  
      def get_local_ref
        get_ref "refs\/heads\/#{@branch}"
      end
  
      def get_remote_ref
        get_ref "refs\/remotes\/origin\/#{@branch}"
      end

      def get_remote_origin
        url = nil 
        result = Maestro::Util::Shell.run_command("cd #{@path} && #{@env}#{@executable} config --get remote.origin.url")

        if result[0].success?
          url = result[1].chomp
        end

        return url
      end

      def get_committer_author_info
        info = {
          :committer_email => '',
          :committer_name => '',
          :author_email => '',
          :author_name => ''
        }
  
        result = Maestro::Util::Shell.run_command("cd #{@path} && " + 'git log -1 --pretty=format:%ce,%cN\|%ae,%aN')
        # Result[0] = exitcode obj, Result[1] = output
        if result[0].success?
          data = result[1].chomp
          peeps = data.split('|')
  
          if peeps.size > 0
            committer = peeps[0].split(',')
            info[:committer_email] = committer[0]
            info[:committer_name] = committer[1]
          end
  
          if peeps.size > 1
            author = peeps[1].split(',')
            info[:author_email] = author[0]
            info[:author_name] = author[1]
          end
        else
          write_output("\nUnable to retrieve committer/author info.\n#{result[1]}")
        end
  
        info
      end

      # Get a list of ticket id's (from git commit subject lines)
      # Assume format is "STRING-NUMBER<space>"*.  eg: "JIRA-123 JIRA-456"
      # Gets tickets from all commit subjects between last & this - so if last was a long time ago,
      # this list may be quite long
      # with possible bracketing [], {}, (), <> on each one.
      # @param previous_hash The hash that was last checked out for this repo
      # @param this_hash The hash that was just checked out for this repo
      def get_tickets(previous_hash, this_hash)
        tickets = []
        range = (previous_hash && !previous_hash.empty?) ? "#{previous_hash}...#{this_hash}" : '-1'

        result = Maestro::Util::Shell.run_command("cd #{@path} && git log #{range} --pretty=format:%s")
        # Result[0] = exitcode obj, Result[1] = output
        if result[0].success?
          subjects = result[1].split("\n")

          subjects.each do |subject|
            tickets += subject.scan(/\[(\w+-\d+)\]/) +
              subject.scan(/\((\w+-\d+)\)/) +
              subject.scan(/{(\w+-\d+)}/) +
              subject.scan(/<(\w+-\d+)>/)
          end
        else
          write_output("\nUnable to retrieve ticket info from commit message.\n#{result[1]}")
        end

        # Ensure we only return each ticket once regardless of how many times it shows up
        tickets.flatten.uniq.compact
      end
    end
  end
end
