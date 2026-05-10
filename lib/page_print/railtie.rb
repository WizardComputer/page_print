module PagePrint
  class Railtie < ::Rails::Railtie
    initializer 'page_print.configure_resource_fetcher' do
      PagePrint.resource_fetcher ||= PagePrint::RailsResourceFetcher.new
    end

    initializer 'page_print.set_base_url' do
      ActiveSupport.on_load(:action_controller_base) do
        around_action do |_controller, action|
          PagePrint.with_base_url(request.base_url) { action.call }
        end
      end
    end
  end
end
