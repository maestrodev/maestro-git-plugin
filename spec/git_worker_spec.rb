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

describe MaestroDev::Plugin::GitWorker do

  let(:clone_fields) {{
    'branch' => 'master',
    'path' => @test_wc_path,
    'url' => @test_repo_path,
    'composition' => 'test',
    'composition_id' => 1
  }}
  let(:workitem) {{'fields' => fields}}
  let(:default_path) { File.expand_path("~/wc/test-1") }

  before(:all) do
    Maestro::MaestroWorker.mock!

    @dt = DateTime.now.strftime('%d%b%Y%H%M%S').to_s
    @test_wc_path = "/tmp/maestro-git-wc"
    @test_repo_path = "/tmp/maestro-git-repo"
    @other_repo_path = "/tmp/some-other-git-repo"
    FileUtils.rm_rf @test_repo_path

    Dir::mkdir(@test_repo_path)
    File.open("#{@test_repo_path}/README", 'w') {|f| f.write("Test") }
    `cd #{@test_repo_path} && git init && git add README && git commit -m '[TICKET-1] [FEATURE-1] readme'`
  end

#  it 'should use a default path when path is not set' do
#    @git_participant.expects(:workitem).at_least_once.returns(workitem)
#    expect(@git_participant.default_path).to eq(File.expand_path("~/wc/test-a-composition--1"))
#  end
 
  before(:each) do
    FileUtils.rm_rf default_path
    FileUtils.rm_rf @test_wc_path
  end

  def initial_clone
    subject.perform(:clone, {'fields' => clone_fields})
    `cd #{@test_wc_path} && git config user.name Test && git config user.email test@example.com`
    expect(subject.error).to be_nil
  end

  describe 'clone()' do

    let(:fields) { clone_fields }
    before do
      subject.perform(:clone, workitem)
    end

    context 'when path is not set' do
      let(:fields) { super().reject{|k,v| k=='path'} }

      it("should not error") { expect(subject.error).to be_nil, subject.output }
      it("should use the default path") { expect(subject.read_output_value('repo_path')).to eq(default_path) }
      it("should create the default path dir") { expect(File.exists?(default_path)).to be_true, subject.output }
    end

    it 'should clone some code' do
      modtime = File.mtime(@test_wc_path)
      expect(subject.error).to be_nil
      expect(File.exists?(@test_wc_path)).to be_true
      sleep(1)
      workitem['fields']['clean_working_copy'] = false

      # Do it again!
      subject.perform(:clone, workitem)
      
      expect(modtime).to eql(modtime = File.mtime(@test_wc_path))
      expect(subject.error).to be_nil
      expect(File.exists?(@test_wc_path)).to be_true
      
      workitem['fields']['clean_working_copy'] = true
        
      # One more time - should revert change      
      subject.perform(:clone, workitem)
      
      expect(modtime).not_to eql(modtime = File.mtime(@test_wc_path))
      expect(subject.error).to be_nil
      expect(File.exists?(@test_wc_path)).to be_true
    end

    it 'should get the latest reference' do
      expect(File.exists?(@test_wc_path)).to be_true
      expect(subject.read_output_value('reference')).not_to be_nil
    end

    it "should set not needed if reference matches previous build" do
      expect(File.exists?(@test_wc_path)).to be_true
      
      expect(subject.error).to be_nil
      workitem['fields']['__previous_context_outputs__'] = {"reference"=>subject.read_output_value('reference')}

      subject.expects(:not_needed)
      subject.perform(:clone, workitem)
    end
    
    it 'should get the ticket from the latest commit' do
      expect(File.exists?(@test_wc_path)).to be_true      
      expect(subject.read_output_value('tickets')).to eq(['TICKET-1', 'FEATURE-1'])
    end    

    context 'when cloning fails' do
      let(:fields) { super().merge({'url' => "http://repo.or.cz/asdfasdf/adfasdf.git"}) }

      it 'should detect error' do
        expect(subject.error).not_to be_nil
        expect(subject.error).to eq('Error cloning repo')
        expect(subject.output).to match("http://repo.or.cz/asdfasdf/adfasdf.git/")

        expect(File.exists?(@test_wc_path)).to be_false
      end
    end
    
    it 'should pull instead of clone on the second call' do
      # ensure creation time is the same after a second clone
      readme = "#{@test_repo_path}/README"
      f = File.new(readme)
      time = f.ctime
      
      subject.perform(:clone, workitem)

      expect(subject.error).to be_nil
      expect(File.exists?(@test_wc_path)).to be_true
      expect(File.exists?(readme)).to be_true
      expect(time).to eql(f.ctime)
    end

    it 'should fail to pull if existing repo points to different url' do
      workitem['fields']['url'] = @other_repo_path 
      subject.perform(:clone, workitem)

      expect(subject.error).to include('squatting')
    end

  end


  describe 'branch()' do

    let(:fields) {{'path' => @test_wc_path, 'remote_repo' => "origin", 'branch_name' => "test_branch_#{@dt}"}}

    before(:each) do
      initial_clone
      subject.perform(:branch, workitem)
    end

    it { expect(subject.error).to be_nil }
    #it { expect(File.exists?(@test_wc_path)).to be_true }
     
    context 'when creating new branch fails' do
      let(:fields) { super().merge({'path' => "/asdfasd/asdfasd"}) }

      it 'should detect error' do
        expect(subject.output).not_to include("Pushing to")
        expect(subject.output).to include("No such file or directory")
        expect(subject.error).not_to be_nil
        expect(subject.error).to eq('Error creating the branch')
        # expect(File.exists?(@test_wc_path).to be_false
      end
    end
  end

  describe 'tag()' do
    let(:fields) {{'path' => @test_wc_path, 'tag_name' =>"test_tag_v#{@dt}", 'message' => "tag test message", 'remote_repo' => "origin", 'remote_branch' => "master"}}

    before(:each) do
      initial_clone
      subject.perform(:tag, workitem)
    end

    it 'should create a new tag' do
      expect(subject.error).to be_nil
    end
     
    context 'when creating new tag fails' do
      let(:fields) { super().merge({'path' => "/asdfasd/asdfasd"}) }

      it 'should detect error if creating new tag fails' do
        expect(subject.output).not_to include("Pushing to")
        expect(subject.output).to include("No such file or directory")
        expect(subject.error).not_to be_nil
        expect(subject.error).to eq('Error tagging the repo')
      end
    end
  end
end
