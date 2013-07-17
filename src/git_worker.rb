# Copyright (c) 2013 MaestroDev.  All rights reserved.
require 'maestro_plugin'
require 'maestro_shell'

module MaestroDev
  class ConfigError < StandardError
  end

  class GitError < StandardError
  end
  
  class GitWorker < Maestro::MaestroWorker

    def clone
      write_output("\nStarting GIT CLONE task...\n", :buffer => true)
      
      begin
        validate_clone_parameters
        
        Maestro.log.info "Inputs:\n  path =       #{@path}\n  url =        #{@url}\n  branch =      #{@branch}\n  environment = #{@environment}\n  executable =  #{@executable}"

        # save the path for later tasks
        set_field('scm_path', @path)
        set_field('git_path', @path)

        if File.exists? @path and @clean_working_copy
          write_output("\nDeleting old path - #{@path}", :buffer => true)
          FileUtils.rm_rf @path
        end

        if File.exists? @path
          # pull instead of clone
          Maestro.log.debug "Git clone: #{@path} exists, pulling instead"
          write_output("\nUpdating repo - #{@url} at #{@path}\n", :buffer => true)
          clone_script =<<-PULL
cd #{@path} && #{@env}#{@executable} pull
PULL
        else
          # first clone
          write_output("\nCloning repo - #{@url} to #{@path}\n", :buffer => true)
          clone_script =<<-CLONE
#{@env}#{@executable} clone -v #{@url} #{@path}
CLONE
        end

        shell = Maestro::Util::Shell.new
        shell.create_script(clone_script)
        write_output("\nRunning command:\n----------\n#{clone_script.chomp}\n----------\n")
        shell.run_script_with_delegate(self, :on_output)
        raise GitError, "Error cloning repo #{shell.output}" unless shell.exit_code.success?
      
        unless !shell.exit_code.success? or @branch.empty? or @branch == "master" 
          checkout = Maestro::Util::Shell.new
          checkout_script =<<-CHECKOUT
cd #{@path} && #{@env}#{@executable} checkout #{@branch}
CHECKOUT
        
          checkout.create_script(checkout_script)
          write_output("\nRunning command:\n----------\n#{checkout_script.chomp}\n----------\n")
          checkout.run_script_with_delegate(self, :on_output)
          raise GitError, "Error on branch checkout #{shell.output}" unless checkout.exit_code.success?
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

        if !latest_ref.nil? and !latest_ref.empty? and latest_ref == local_ref and !get_field('force_build')
          write_output "\nReference From Previous Build #{latest_ref} Equals Latest From Repo Build Not Needed"
          not_needed
        end
      rescue ConfigError, GitError => e
        @error = e.message
      rescue Exception => e
        @error = "Error executing Git Clone Task: #{e.class} #{e}"
        Maestro.log.warn("Error executing Git Clone Task: #{e.class} #{e}: " + e.backtrace.join("\n"))
      end
      
      write_output "\n\nGIT CLONE task complete\n"
      set_error(@error) if @error
    end

    def branch
      write_output("\nStarting GIT BRANCH task...\n", :buffer => true)
      
      begin
        validate_branch_parameters
        
        Maestro.log.info "Inputs:\n  path =       #{@path}\n  branch_name = #{@branch}\n  environment = #{@environment}\n  executable =  #{@executable}\n  remote_repo = #{@remote_repo}"

        write_output("\nCreating the branch: #{@branch} in the repo at #{@path}\n", :buffer => true)
      
        branch_script =<<-BRANCH
cd #{@path} && #{@env} \
#{@executable} branch -v #{@branch} && \
#{@executable} push -v #{@remote_repo} #{@branch}
BRANCH
      
        shell = Maestro::Util::Shell.new
        shell.create_script(branch_script)
        write_output("\nRunning command:\n----------\n#{branch_script.chomp}\n----------\n")
        shell.run_script_with_delegate(self, :on_output)
      
        @error = "Error creating the branch #{shell.output}" unless shell.exit_code.success?
      rescue ConfigError, GitError => e
        @error = e.message
      rescue Exception => e
        @error = "Error executing Git Branch Task: #{e.class} #{e}"
        Maestro.log.warn("Error executing Git Branch Task: #{e.class} #{e}: " + e.backtrace.join("\n"))
      end

      write_output "\n\nGIT BRANCH task complete\n"
      set_error(@error) if @error
    end

    def tag
      write_output("\nStarting GIT TAG task...\n", :buffer => true)
      
      begin
        validate_tag_parameters
        
        Maestro.log.info "Inputs:\n" \
          "  path =            #{@path}\n" \
          "  branch_name =     #{@branch}\n" \
          "  environment =     #{@environment}\n" \
          "  executable =      #{@executable}\n" \
          "  remote_repo =     #{@remote_repo}\n" \
          "  tag_name =        #{@tag_name}\n" \
          "  commit_checksum = #{@commit_checksum}\n" \
          "  message =         #{@message}"

        write_output("Tagging the repo at #{@path} with tagname: #{@tag_name}", :buffer => true)
        write_output(" and commit checksum starting with #{@commit_checksum}", :buffer => true) unless @commit_checksum.empty?
        write_output(" with the tag message: '#{workitem['fields']['message']}'", :buffer => true) if !workitem['fields']['message'].nil? && workitem['fields']['message']!=""
        write_output(" and pushing it to the remote repository: #{@remote_repo} #{@branch}", :buffer => true)

        tagcommand = "tag -a #{@tag_name}"
        tagcommand += " #{@commit_checksum}" unless @commit_checksum.empty?
        tagcommand += " -m '#{@message}'" unless @message.empty?

        pushcommand = "push -v --tags #{@remote_repo} #{@branch}"

        tag_script =<<-TAG
cd #{@path} && #{@env} \
#{@executable} #{tagcommand} && \
#{@executable} #{pushcommand}
TAG

        shell = Maestro::Util::Shell.new
        shell.create_script(tag_script)
        write_output("\nRunning command:\n----------\n#{tag_script.chomp}\n----------\n")
        shell.run_script_with_delegate(self, :on_output)

        @error = "Error Tagging in git #{shell.output}" unless shell.exit_code.success?
      rescue ConfigError, GitError => e
        @error = e.message
      rescue Exception => e
        @error = "Error executing Git Tag Task: #{e.class} #{e}"
        Maestro.log.warn("Error executing Git Tag Task: #{e.class} #{e}: " + e.backtrace.join("\n"))
      end

      write_output "\n\nGIT TAG task complete\n"
      set_error(@error) if @error
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

    def booleanify(value)
      res = false

      if value
        if value.is_a?(TrueClass) || value.is_a?(FalseClass)
          res = value
        elsif value.is_a?(Fixnum)
          res = value != 0
        elsif value.respond_to?(:to_s)
          value = value.to_s.downcase

          res = (value == 't' || value == 'true')
        end
      end

      res
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
      @clean_working_copy = booleanify(get_field('clean_working_copy', false))
      @force_build = booleanify(get_field('force_build', false))

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
      raise GitError, "Error Detecting Reference: #{show_ref.output}" unless show_ref.exit_code.success?

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

    def get_committer_author_info
      info = {
        :committer_email => '',
        :committer_name => '',
        :author_email => '',
        :author_name => ''
      }

      result = Maestro::Util::Shell.run_command('git log -1 --pretty=format:%ce,%cN\|%ae,%aN')
      # Result[0] = exitcode obj, Result[1] = output
      if result[0].success?
        data = result[1]
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
      end

      info
    end
  end
end
