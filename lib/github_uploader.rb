require "rest-client"
require "github_api"

class GithubUploader
  AUTH_NOTE = "Github Uploader (gem)"

  def self.setup_uploader
    # get the github user name
    login = `git config github.user`.chomp

    # get repo from git config's origin url
    origin = `git config remote.origin.url`.chomp # url to origin
    # extract USERNAME/REPO_NAME
    # sample urls: https://github.com/emberjs/ember.js.git
    #              git://github.com/emberjs/ember.js.git
    #              git@github.com:emberjs/ember.js.git
    #              git@github.com:emberjs/ember.js

    repoUrl = origin.match(/github\.com[\/:]((.+?)\/(.+?))(\.git)?$/)
    username = repoUrl[2] # username part of origin url
    repo = repoUrl[3] # repository name part of origin url

    uploader = GithubUploader.new(login, username, repo)
    uploader.authorize

    uploader
  end

  def self.upload_file(uploader, filename, description, file)
    print "Uploading #{filename}..."
    if uploader.upload_file(filename, description, file)
      puts "Success"
    else
      puts "Failure"
    end
  end

  def initialize(login, username, repo, root=Dir.pwd)
    @login    = login
    @username = username
    @repo     = repo
    @root     = root
    @token    = check_token
  end

  def authorized?
    !!@token
  end

  def token_path
    File.expand_path(".github-upload-token", @root) 
  end

  def check_token
    File.exist?(token_path) ? File.open(token_path, "rb").read : nil
  end

  def authorize
    return if authorized?

    puts "There is no file named .github-upload-token in this folder. This file holds the OAuth token needed to communicate with GitHub."
    puts "You will be asked to enter your GitHub password so a new OAuth token will be created."
    print "GitHub Password: "
    system "stty -echo" # disable echoing of entered chars so password is not shown on console
    pw = STDIN.gets.chomp
    system "stty echo" # enable echoing of entered chars
    puts ""

    # check if the user already granted access for "Githhub Uploader (gem)" by checking the available authorizations
    response = RestClient.get "https://#{@login}:#{pw}@api.github.com/authorizations"
    JSON.parse(response.to_str).each do |auth|
      if auth["note"] == AUTH_NOTE
        # user already granted access, so we reuse the existing token
        @token = auth["token"]
      end
    end

    ## we need to create a new token
    unless @token
      payload = {
        :scopes => ["public_repo"],
        :note => AUTH_NOTE
        :note_url => "https://github.com/#{@username}/#{@repo}"
      }
      response = RestClient.post "https://#{@login}:#{pw}@api.github.com/authorizations", payload.to_json, :content_type => :json
      @token = JSON.parse(response.to_str)["token"]
    end

    # finally save the token into .github-upload-token
    File.open(".github-upload-token", 'w') {|f| f.write(@token)}
  end

  def upload_file(filename, description, file)
    return false unless authorized?

    gh = Github.new :user => @username, :repo => @repo, :oauth_token => @token

    # remvove previous download with the same name
    gh.repos.downloads do |download|
      if filename == download.name
        gh.repos.delete_download @username, @repo, download.id
        break
      end
    end

    # step 1
    hash = gh.repos.create_download @username, @repo,
      "name" => filename,
      "size" => File.size(file),
      "description" => description,
      "content_type" => "application/json"

    # step 2
    gh.repos.upload hash, file

    return true
  end

end