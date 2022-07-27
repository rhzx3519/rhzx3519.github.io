```shell
# 1. 安装bundle
$ brew install bundle

# 2. 安装jekyll
$ sudo gem install jekyll
$ sudo gem install jekyll bundler

# 3. 编译 jekyll
cd docs & bundle install

# 4. 本地起服务
bundle exec jekyll serve --trace
```

* 配置Gemfile
```yaml
gem "jekyll", "~> 3.9.2"
# This is the default theme for new Jekyll sites. You may change this to anything you like.
gem 'jekyll-theme-merlot', '~> 0.2.0'
# If you want to use GitHub Pages, remove the "gem "jekyll"" above and
# uncomment the line below. To upgrade, run `bundle update github-pages`.
gem 'github-pages', '~> 227', group: :jekyll_plugins
```

然后重新build
```shell
bundle install
```