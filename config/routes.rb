Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"

  resources :artists, only: %i[index show]
  # "albums" in the URL, ReleaseGroup in the code: the model name says what it
  # is precisely, the path says what a person calls it.
  resources :release_groups, path: "albums", as: :albums, only: %i[index show] do
    # Stable, immutable URLs: /albums/1/cover/thumb
    get "cover/:variant", to: "covers#show", as: :cover
  end
  resource :search, only: :show, controller: "search"
  get "search/suggestions", to: "search#suggestions", as: :search_suggestions

  # Physical media is entered by hand — it is the only data here that a library
  # scan cannot rebuild, because a record on a shelf leaves no file behind.
  resources :releases, only: %i[new create edit update destroy]
  # A record pressed before barcodes carries a catalogue number and nothing
  # else machine-readable, so that number is the way in.
  resource :catalogue_lookup, only: :show, controller: "catalogue_lookups"
  # Fetched on request rather than with the list: it costs a call per pressing,
  # and it is only wanted when two candidates look alike.
  get "catalogue_lookup/pressing/:mbid", to: "catalogue_lookups#details",
      as: :catalogue_pressing, constraints: { mbid: /[0-9a-fA-F-]{36}/ }
  get "shelf", to: "shelf#show", as: :shelf

  # The digital half of the catalogue is rebuilt by scanning; this is how that
  # is started and watched without a shell.
  resources :scans, only: %i[index create] do
    get "status", on: :collection
  end
end
