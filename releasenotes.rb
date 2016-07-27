#!/usr/bin/env ruby
require "thor"
require "git"
require "erb"
require "ostruct"
require 'pry'

class ReleaseNotes < Thor
  @@GENERATE_TEMPLATE = <<-'END_TEMPLATE'
## Customer Facing Changes

## Non-Customer Facing Changes

## Stats

* <%= commits.select{|c| c.issues}.length %> Issues Addressed
* <%= commits.select{|c| c.pull}.length %> Pull Requests Merged
* <%= commits.length %> Commits by <%= commits.select{|c| c.author}.uniq{|c| c.author }.length %> Authors

**[Complete GitHub History](<%= opts[:github] %>/compare/<%= opts[:from] %>...<%= opts[:to] %>)**

## Issues Addressed
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
  def generate
    git = Git.open(options[:repo] || '.')

    opts = {
      repo:   options[:repo],
      github: options[:github],
    }

    opts[:from] = options[:from] || (git.tags.last ? git.tags.last.name : log.last) # most recent tag or earliest commit
    opts[:to]   = options[:to]   || log.first # most recent

    commits = []
    pr_number_regex = /#(\d+)/
    find_pr_regex = /Merge pull request \[#(\d+)\]/
    find_issues_regex = /(?:addresses|fixes|closes) \[#(\d+)\]/i

    git.log.between(opts[:from], opts[:to]).each do |commit|
      message = commit.message

      message.gsub!(pr_number_regex, "[#\\1](#{opts[:github]}/pull/\\1)")

      parts = message.split("\n\n", 2)

      commits << OpenStruct.new(
        author:  commit.author.name,
        sha:     commit.sha,
        subject: parts[0],
        body:    parts[1],
        pull:    commit.message.scan(find_pr_regex).first,
        issues:  commit.message.scan(find_issues_regex).first,
      )

    end
    puts ERB.new(@@GENERATE_TEMPLATE, nil, '<>').result binding
  end
end

ReleaseNotes.start
