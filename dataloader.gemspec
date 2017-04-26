$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "dataloader"
  s.version     = "0.0.0"
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Adam Stankiewicz"]
  s.email       = ["sheerun@sher.pl"]
  s.homepage    = "https://github.com/sheerun/dataloader"
  s.summary     = %q{Batch data loading, works great with graphql}
  s.description = %q{A data loading utility to batch loading of promises. It can be used with graphql gem.}
  s.license     = 'MIT'

  s.add_runtime_dependency('concurrent-ruby', '~> 1')
  s.add_runtime_dependency('promise.rb', '~> 0.7')

  s.files         = Dir['lib/**/*'] + %w(LICENSE README.md)
  s.require_paths = ["lib"]
end
