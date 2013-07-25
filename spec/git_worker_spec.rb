# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
# 
#  http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

require 'spec_helper'

describe MaestroDev::GitPlugin::GitWorker do

  before(:all) do
    Maestro::MaestroWorker.mock!

    @dt = DateTime.now.strftime('%d%b%Y%H%M%S').to_s
    @test_wc_path = "/tmp/maestro-git-wc"
    @test_repo_path = "/tmp/maestro-git-repo"
    FileUtils.rm_rf @test_wc_path
    FileUtils.rm_rf @test_repo_path

    Dir::mkdir(@test_repo_path)
    File.open("#{@test_repo_path}/README", 'w') {|f| f.write("Test") }
    `cd #{@test_repo_path} && git init && git add README && git commit -m 'readme'`
  end

#  it 'should use a default path when path is not set' do
#    workitem = {'fields' => {'composition' => ' test a composition #$ ', 'composition_id' => 1}}
#    @git_participant.expects(:workitem).at_least_once.returns(workitem)
#    @git_participant.default_path.should eq(File.expand_path("~/wc/test-a-composition--1"))
#  end
 
  describe 'clone()' do
    before(:each) do
      FileUtils.rm_rf @test_wc_path
    end

    it 'should clone to default path when path is not set' do
      workitem = {'fields' => {'branch' => 'master', 'url' => @test_repo_path, 'composition' => 'test', 'composition_id' => 1}}

      subject.perform(:clone, workitem)
      
      workitem['fields']['__error__'].should be_nil
      path = workitem['fields']['__context_outputs__']['repo_path']
      path.should eq(File.expand_path("~/wc/test-1"))
      File.exists?(path).should be_true
      FileUtils.rm_rf path
    end

    it 'should clone some code' do
      workitem = {'fields' => {'branch' => 'master', 'path' => @test_wc_path, 'url' => @test_repo_path}}
      
      subject.perform(:clone, workitem)
      
      modtime = File.mtime(@test_wc_path)
      workitem['fields']['__error__'].should be_nil
      File.exists?(@test_wc_path).should be_true
      sleep(1)
      workitem['fields']['clean_working_copy'] = false

      # Do it again!
      subject.perform(:clone, workitem)
      
      modtime.should eql(modtime = File.mtime(@test_wc_path))
      workitem['fields']['__error__'].should be_nil
      File.exists?(@test_wc_path).should be_true
      
      workitem['fields']['clean_working_copy'] = true
        
      # One more time - should revert change      
      subject.perform(:clone, workitem)
      
      modtime.should_not eql(modtime = File.mtime(@test_wc_path))
      workitem['fields']['__error__'].should be_nil
      File.exists?(@test_wc_path).should be_true
    end

    it 'should get the latest reference' do
      workitem = {'fields' => {'branch' => 'master', 'path' => @test_wc_path, 'url' => @test_repo_path}}

      subject.perform(:clone, workitem)

      File.exists?(@test_wc_path).should be_true
      
      ref = workitem['fields']['__context_outputs__']['reference']
      ref.should_not be_nil
    end    

    it "should set not needed if reference matches previous build" do
      workitem = {'fields' => {'branch' => 'master', 'path' => @test_wc_path, 'url' => @test_repo_path}}

      subject.perform(:clone, workitem)

      File.exists?(@test_wc_path).should be_true
      
      workitem['fields']['__error__'].should be_nil
      workitem['fields']['__previous_context_outputs__'] = {"reference"=>workitem['fields']['__context_outputs__']['reference']}

      subject.expects(:not_needed)
      subject.perform(:clone, workitem)
    end
    
    it 'should detect error if clone some code fails' do
      workitem = {'fields' => {'branch' => 'master', 'path' => @test_wc_path, 'url' => "http://repo.or.cz/asdfasdf/adfasdf.git"}}
      
      subject.perform(:clone, workitem)
      
      workitem['fields']['__error__'].should_not be_nil
      workitem['fields']['__error__'].should include("http://repo.or.cz/asdfasdf/adfasdf.git/info/refs")
      File.exists?(@test_wc_path).should be_false
    end
    
    it 'should pull instead of clone on the second call' do
      workitem = {'fields' => {'branch' => 'master', 'path' => @test_wc_path, 'url' => @test_repo_path}}

      subject.perform(:clone, workitem)

      # ensure creation time is the same after a second clone
      readme = "#{@test_repo_path}/README"
      f = File.new(readme)
      time = f.ctime
      
      subject.perform(:clone, workitem)

      workitem['fields']['__error__'].should be_nil
      File.exists?(@test_wc_path).should be_true
      File.exists?(readme).should be_true
      time.should eql(f.ctime)
    end

  end



  describe 'branch()' do
     before(:each) do
       FileUtils.rm_rf @test_wc_path
       workitem = {'fields' => {'branch' => "master", 'path' => @test_wc_path, 'url' => @test_repo_path}}

       subject.perform(:clone, workitem)

       `cd #{@test_wc_path} && git config user.name Test && git config user.email test@example.com`

       workitem['fields']['__error__'].should be_nil
     end
     
     it 'should create a new branch' do
       workitem = {'fields' => {'path' => @test_wc_path, 'remote_repo' => "origin", 'branch_name' => "test_branch_#{@dt}"}}

       subject.perform(:branch, workitem)
       
       workitem['fields']['__error__'].should be_nil
      # File.exists?(@test_wc_path).should be_true
     end
     
     it 'should detect error if creating new branch fails' do
       workitem = {'fields' => {'path' => "/asdfasd/asdfasd", 'remote_repo' => "origin", 'branch_name' => "test_branch_#{@dt}"}}

       subject.perform(:branch, workitem)

       workitem['__output__'].should_not include("Pushing to")
       workitem['fields']['__error__'].should_not be_nil
       workitem['fields']['__error__'].should include("No such file or directory")
      # File.exists?(@test_wc_path).should be_false
     end
  end

  describe 'tag()' do
     before(:each) do
       FileUtils.rm_rf @test_wc_path
       workitem = {'fields' => {'branch' => "master", 'path' => @test_wc_path, 'url' => @test_repo_path}}

       subject.perform(:clone, workitem)

       `cd #{@test_wc_path} && git config user.name Test && git config user.email test@example.com`
       workitem['fields']['__error__'].should be_nil
     end
     
     it 'should create a new tag' do
       workitem = {'fields' => {'path' => @test_wc_path, 'tag_name' =>"test_tag_v#{@dt}", 'message' => "tag test message", 'remote_repo' => "origin", 'remote_branch' => "master"}}

       subject.perform(:tag, workitem)
       
       workitem['fields']['__error__'].should be_nil
     end
     
     it 'should detect error if creating new tag fails' do
       workitem = {'fields' => {'path' => "/asdfsaf/sdfsfd", 'tag_name' =>"test_tag_v#{@dt}", 'message' => "tag test message", 'remote_repo' => "origin", 'remote_branch' => "master"}}

       subject.perform(:tag, workitem)

       workitem['__output__'].should_not include("Pushing to")
       workitem['fields']['__error__'].should_not be_nil
       workitem['fields']['__error__'].should include("No such file or directory")
     end
     
  end

  after(:all) do
    #FileUtils.rm_rf @test_wc_path
    #FileUtils.rm_rf @test_repo_path
  end

  
#  
#  
#  
#  
#  
#  
#  
#  >>>>>
#  before(:each) do
#    FileUtils.rm '/tmp/shell.sh' if File.exists? '/tmp/shell.sh'
#  end
#
#  describe 'valid_workitem?' do
#    it "should validate fields" do
#      workitem = {'fields' =>{}}
#
#      subject.perform(:execute, workitem)
#
#      workitem['fields']['__error__'].should include('missing field command_string')
#    end
#  end
#
#  describe 'execute' do
#    before :all do
##      @workitem =  {'fields' => {'tasks' => '',
##                                 'path' => @path,
##                                 'ant_version' => '1.8.2'}}
#    end
#
#    it 'should return successfully with valid command' do
#      command = 'touch /tmp/archive_test.tar.gz && ls -l /tmp/archive_test.tar.gz'
#      workitem = {'fields' => {
#        'command_string' => command, 
#        'environment' => 'PATH=$PATH;'
#      }}
#
#      subject.perform(:execute, workitem)
#
#      workitem['fields']['__error__'].should be_nil
#      workitem['__output__'].should include("archive_test.tar.gz")
#    end
#    
#    it 'should return successfully with invalid command' do
#      command = 'ls -l /blahdy/'
#      workitem = {'fields' => {
#        'command_string' => command
#      }}
#
#      subject.perform(:execute, workitem)
#
#      workitem['fields']['__error__'].should include "No such file or directory"
#      workitem['__output__'].should include "No such file or directory"
#    end
#
#    it 'should write the output to lucee' do
#      command = 'echo my message'
#      workitem = {'fields' => {
#        'command_string' => command
#      }}
#
#      subject.perform(:execute, workitem)
#
#      workitem['fields']['__error__'].should be_nil
#      workitem['__output__'].should include("my message\n")
#    end
#  end
end
