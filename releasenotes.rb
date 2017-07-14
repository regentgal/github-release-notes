#!/usr/bin/env ruby
# coding: utf-8

require "thor"
require "git"
require "octokit"
require "logger"
require "erb"
require "ostruct"

class GitHubCommitTags
  attr_reader :client, :repository, :logger

  def initialize(access_token:, repository:, logger: Logger.new(STDERR))
    @client = Octokit::Client.new(access_token: access_token)
    @repository = repository
    @logger = logger
  end

  def special_deploy_requirements?(sha)
    search_results = client.search_issues("#{sha} repo:#{repository} is:merged")

    count = search_results.total_count

    if count == 0
      # There isn't a corresponding PR for this commit. This usually
      # occurs for the commit that merges the master branch into the
      # deploy branch.
      return false
    elsif count > 1
      logger.warn("SHA #{sha} had #{search_results.total_count} issues, not just one; ignoring.")
      return false
    end

    pr = search_results.items.first
    labels = pr.labels.map(&:name)

    labels.any? { |label| label =~ /special deploy requirements/i }
  end
end

class ReleaseNotes < Thor
  @@GENERATE_TEMPLATE = <<-'END_TEMPLATE'

# <%= title %>

## Customer Facing Changes

## Non-Customer Facing Changes

## Stats

* <%= commits.select{|c| c.issues}.length %> Issues Addressed
* <%= commits.select{|c| c.pull}.length %> Pull Requests Merged
* <%= commits.length %> Commits by <%= commits.select{|c| c.author}.uniq{|c| c.author }.length %> Authors

**[Complete GitHub History](<%= opts[:github] %>/compare/<%= opts[:from] %>...<%= opts[:to] %>)**

## Issues Closed By Commits
<% commits.select{|c| c.issues }.each do |commit| %>
  <% commit.issues.each do |issue| %>
* [#<%= issue %>](<%= opts[:github] %>/issues/<%= issue %>)
  <% end %>
<% end %>

## Pull Requests

<% commits.select{|c| c.pull }.each do |commit| %>
* [#<%= commit.pull.first %>](<%= opts[:github] %>/pull/<%= commit.pull.first %>) — <%= commit.body %>
<% end %>

## Commit History

<% commits.each do |commit| %>
<% if commit.pull %>

### [Pull Request] <%= commit.subject %>
<% else %>

**[Commit] <%= commit.subject %>**
<% end %>

_by [<%= commit.author %>](<%= opts[:github] %>/commit/<%= commit.sha %>)_

<%= commit.body %>

<% end %>

# Configuration

```
# Generated <%= Time.now %>
--repo   <%= opts[:repo] %>
--from   <%= opts[:from] %>
--to     <%= opts[:to] %>
--github <%= opts[:github] %>
```


END_TEMPLATE

  desc "generate", "generate release notes"
  option :repo
  option :from
  option :to
  option :github
  option :gh_token
  def generate
    git = Git.open(options[:repo] || '.')

    opts = {
      repo:   options[:repo],
      github: options[:github],
    }

    opts[:from] = options[:from] || (git.tags.last ? git.tags.last.name : git.log.last) # most recent tag or earliest commit
    opts[:to]   = options[:to]   || git.log.first # most recent

    gh_url = URI.parse(options[:github])
    gh_repo_name = gh_url.path.split('/').reject(&:empty?).join('/')
    commit_tags = GitHubCommitTags.new(
      access_token: options[:gh_token],
      repository: gh_repo_name
    )

    title = (opts[:to].is_a? String) ? git.tag(opts[:to]).message : "Untitled"

    commits = []
    pr_number_regex = /#(\d+)/
    find_pr_regex = /Merge pull request \[#(\d+)\]/
    find_issues_regex = /(?:close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved) \[#(\d+)\]/i

    git.log(nil).between(opts[:from], opts[:to]).each do |commit|
      message = commit.message

      message.gsub!(pr_number_regex, "[#\\1](#{opts[:github]}/pull/\\1)")

      parts = message.split("\n\n", 2)

      merge_commit = commit.parents.size > 1
      special_deploy_requirements = merge_commit && commit_tags.special_deploy_requirements?(commit.sha)

      commits << OpenStruct.new(
        author:  commit.author.name,
        sha:     commit.sha,
        subject: parts[0],
        body:    parts[1],
        pull:    commit.message.scan(find_pr_regex).first,
        issues:  commit.message.scan(find_issues_regex).first,
        special_deploy_requirements: special_deploy_requirements,
      )

    end
    puts ERB.new(@@GENERATE_TEMPLATE, nil, '<>').result binding

    commits_with_special_deploy_requirements = commits.select(&:special_deploy_requirements)
    unless commits_with_special_deploy_requirements.empty?
      puts <<~EOF
      ====================

      WARNING: There are commits with special deploy requirements!
      EOF

      commits_with_special_deploy_requirements.each do |commit|
        Array(commit.pull).each do |pull|
          puts "* #{opts[:github]}/pull/#{pull}"
        end
      end
    end
  end
end

ReleaseNotes.start
