ActionController::Routing::Routes.draw do |map|
  # The priority is based upon order of creation: first created -> highest priority.
  
  # Sample of regular route:
  # map.connect 'products/:id', :controller => 'catalog', :action => 'view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  # map.purchase 'products/:id/purchase', :controller => 'catalog', :action => 'purchase'
  # This route can be invoked with purchase_url(:id => product.id)
  #
  # named route for loading css files and images
  map.dynamic 'dynamic/*name', :controller => 'setup/dynamic_strings'

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   map.resources :products
  map.resources :card_transactions
  map.resources :paypal_transactions, :only => [:new,:create], :collection => {:ipn => :get}, :member => {:wait_for_confirm => :get}
  map.resources :extra_charges, :except => [:create, :new], :member => {:update_monthly => :put}, :collection => {:monthly_updates => :get} 
  map.resources :payments, :except => [:create, :new]
  map.resources :mail_templates
  map.resources :users
  map.resources :variable_charges
  map.resources :report, :only => :index
  map.resources :admin, :only => :index
  map.resources :maintenance, :only => :index
  map.resources :setup, :only => :index
  map.resources :availables, :only => :update
  map.resources :group, :member => {:found => :get}

  # Sample resource route with options:
  #   map.resources :products, :member => { :short => :get, :toggle => :post }, :collection => { :sold => :get }

  # Sample resource route with sub-resources:
  #   map.resources :products, :has_many => [ :comments, :sales ], :has_one => :seller

  # Sample resource route with more complex sub-resources
  #   map.resources :products do |products|
  #     products.resources :comments
  #     products.resources :sales, :collection => { :recent => :get }
  #   end

  # Sample resource route within a namespace:
  #   map.namespace :admin do |admin|
  #     # Directs /admin/products/* to Admin::ProductsController (app/controllers/admin/products_controller.rb)
  #     admin.resources :products
  #   end

  map.namespace :maintenance do |maintenance|
    maintenance.resources :backup, :only => :index
    maintenance.resources :backup_files, :except => [:new, :edit]
    maintenance.resources :log_files, :only => [:index, :destroy, :show]
    maintenance.resources :restart, :only => :index
    maintenance.resources :troubleshoot, :only => [:index, :destroy]
    maintenance.resources :conflicts, :only => [:index, :show]
  end

  map.namespace :payment do |payment|
    payment.resources :receipts, :only => [:show]
    payment.resources :refunds, :only => [:edit, :update]
  end

  map.namespace :report do |report|
    report.resources :payments, 	  :only => [:new, :create, :update]
    report.resources :transactions, 	  :only => [:new, :create]
    report.resources :occ_sites, 	  :only => [:new, :create]
    report.resources :count_rigs, 	  :only => [:new, :create]
    report.resources :reservations, 	  :only => [:new, :create]
    report.resources :recommenders, 	  :only => [:new, :create]
    report.resources :extras, 		  :only => [:new, :create]
    report.resources :sched_arrs, 	  :only => [:new, :create]
    report.resources :sched_deps, 	  :only => [:new, :create]
    report.resources :card_transactions,  :only => [:new, :create]
    report.resources :archives,		  :only => [:new, :create]
    report.resources :spaces, 		  :only => [:index, :update]
    report.resources :today_checkouts,	  :only => :index
    report.resources :tomorrow_checkouts, :only => :index
    report.resources :dues,		  :only => :index
    report.resources :campers,		  :only => :index
    report.resources :today_checkins, 	  :only => :index
    report.resources :tomorrow_checkins,  :only => :index
  end

  map.namespace :admin do |admin|
    admin.resources :about, :only => :index
    admin.resources :license, :only => :index
    admin.resources :user_manual, :only => :index
  end

  map.namespace :setup do |setup|
    setup.resources :blackout, :except => :show
    setup.resources :campers, :only => [:new, :create]
    setup.resources :discount, :except => :show, :collection => { :sort => :get, :resort => :get }
    setup.resources :extra, :except => :show, :member => {:update_type => :put }, :collection => { :sort => :get, :resort => :get }
    setup.resources :integrations, :only => [:edit, :update]
    setup.resources :remotes, :only => [:edit, :update]
    setup.resources :sitetype, :except => :show, :collection => { :sort => :get, :resort => :get }
    setup.resources :prompts, :except => :show
  end

  # You can have the root of your site routed by hooking up '' 
  # -- just remember to delete public/index.html.
  # map.root :controller => "welcome"
  map.root :controller => "reservation", :action => "list"

  # See how all your routes lay out with "rake routes"


  # Install the default routes as the lowest priority.
  # Note: These default routes make all actions in every controller accessible via GET requests. You should
  # consider removing or commenting them out if you're using named routes and resources.
  map.connect ':controller/:action/:id'
  map.connect ':controller/:action/:id.:format'
  # catch all of the stuff that is left and handle and report it
  map.connect '*anything', :controller => :bogus
end
