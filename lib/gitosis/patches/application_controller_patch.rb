require_dependency 'application_controller'
module Gitosis
  module Patches
    module ApplicationControllerPatch
	  def self.included(base)
        base.class_eval do
          unloadable
        end
        base.send(:prepend_around_filter, :handle_gitosis_project_updates)
      end
	  private
		def handle_gitosis_project_updates
			Thread.current[:gitosis_project_updates]= []

			yield # Continue the filter chain.

			if Thread.current[:gitosis_project_updates].length > 0
				logger.info("Action needs to update Gitosis repositories")
				Gitosis::update_repositories(Thread.current[:gitosis_project_updates])
			end
		end
    end
  end
end

ApplicationController.send(:include, Gitosis::Patches::ApplicationControllerPatch) unless ApplicationController.include?(Gitosis::Patches::ApplicationControllerPatch)