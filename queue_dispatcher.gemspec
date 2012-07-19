# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "queue_dispatcher/version"

Gem::Specification.new do |s|
  s.name        = "queue_dispatcher"
  s.version     = QueueDispatcher::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Philip Kurmann"]
  s.email       = ["philip.kurmann@inwork.ch"]
  s.homepage    = ""
  s.summary     = %q{This Gem installs a queue dispatcher for handling asynchronous tasks}
  s.description = %q{Queue_Dispatcher executes asynchronous tasks in the background.}

  s.add_dependency "sys-proctable", '>= 0.9.1'
  s.add_dependency "deadlock_retry"
  s.add_dependency "spawn", '>= 1.0.0'
  s.add_dependency "haml"
  s.add_dependency "will_paginate"
  s.add_dependency "jquery-rails"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
