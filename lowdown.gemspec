# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'lowdown/version'

Gem::Specification.new do |spec|
  spec.name          = "lowdown"
  spec.version       = Lowdown::VERSION
  spec.authors       = ["Eloy Durán"]
  spec.email         = ["eloy.de.enige@gmail.com"]

  spec.summary       = "A Ruby client for the HTTP/2 version of the Apple Push Notification Service."
  spec.homepage      = "https://github.com/alloy/lowdown"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| File.dirname(f) == "test" }
  spec.bindir        = "bin"
  spec.executables   = "lowdown"
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "http-2", ">= 0.8"

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
