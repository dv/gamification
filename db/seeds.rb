# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

# Use OAuth organisation secrets in production
if Rails.env.production?
  github = Github.new client_id: Rails.application.secrets.github_app_id,
                      client_secret: Rails.application.secrets.github_app_secret,
                      auto_pagination: true

else  # but user tokens in dev
  github = Github.new oauth_token: Rails.application.secrets.github_token,
                      auto_pagination: true
end
coders = Hash.new

# Get contributor statistics for every repo
github.repos.list(org: 'ZeusWPI').each do |repo|
  # Add amount of commits to the corresponding Coder objects in `coders`. Make
  # new Coder objects along the way.
  github.repos.contributors('ZeusWPI', repo.name).each do |cont|
    next if cont.blank?
    if coders.has_key? cont.login
      coders[cont.login].commits += cont.contributions
    else
      coders[cont.login] = Coder.new  github_name: cont.login,
                                      avatar_url: cont.avatar_url,
                                      github_url: cont.html_url,
                                      commits: cont.contributions
    end
  end

  # Add amount of line additions, changes and deletions to the corresponding
  # Coder objects.
  github.repos.stats.contributors('ZeusWPI', repo.name).each do |cont|
    next if cont.blank?
    additions = cont.weeks.map(&:a).sum
    coders[cont.author.login].additions += additions
    coders[cont.author.login].modifications += cont.weeks.map(&:c).sum
    coders[cont.author.login].deletions += cont.weeks.map(&:d).sum
    #coders[cont.author.login].reward loc: additions, reward_bounty_points: false
  end
end

# (a) Fetch the real name of the coder,
# (b) calculate reward and bounty points according to the total score,
# (c) and save all newly created Coder objects.
coders.values.each do |coder|
  github_info = github.users.get(user: coder.github_name)
  coder.full_name = github_info.has_key?(:name) ? github_info.name : ''
  coder.save!
end

# Fetch and store issues for all public repos
github.repos.list(org: 'ZeusWPI', type: 'public') do |repo|
  github.issues.list(user: 'ZeusWPI', repo: repo.name, filter: 'all').each do |issue_hash|
    Issue.create_from_hash issue_hash, repo.name
  end
end
