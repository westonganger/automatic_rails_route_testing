RSpec.describe "All Routes Test", type: :request do

  after(:each) do
    sign_out(:user)
  end

  before(:all) do
    @error_redirect_url = management_root_path

    @all_app_routes = Rails.application.routes.routes.map{|x| ActionDispatch::Routing::RouteWrapper.new(x) }.reject{|x| x.internal? || x.engine? }
    
    total_route_count = @all_app_routes.count
    get_route_count = 0
    tested_routes_count = 0
    
    ignored_routes = [
      "/catch-ids",
      "/management/admin/sidekiq",
      "/management/admin/pghero",
    ]

    ignored_controllers = [
      "errors",
      "management/json",
      /company_sites/,
      /devise/,
    ]

    @scrubbed_routes = []

    @all_app_routes.each do |route| 
      ### SKIP IGNORED CONTROLLERS
      if ignored_controllers.any?{|x| x.is_a?(Regexp) ? (route.controller.to_s =~ x) : (route.controller.to_s == x) }
        next
      end

      ### SKIP IGNORED ROUTES
      if ignored_routes.include?(route.path.split("(").first)
        next
      end

      ### GET METHOD
      if route.verb.blank?
        method = "get" ### REDIRECTS, ETC.
      else
        method = route.verb.to_s.downcase
      end

      if method == "get"
        ### COUNT VALID GET ROUTES
        get_route_count += 1
      else
        ### WE CAN ONLY TEST GET ROUTES AUTOMATICALLY
        ### NON-GET REQUESTS WILL REQUIRE SPECIFIC PARAMS
        next
      end

      ### CHECK FOR REQUIRED PARAMS (TOKEN/ID)
      if route.required_parts.any?
        token = false
        
        ### ATTEMPT TO GET TOKEN/ID FOR ROUTES WITH REQUIRED PARAMS
        case route.path
        when %r{/orders/}
          token = Order.first.try!(:id)
        when %r{/products/}
          token = Product.first.try!(:id)
        when %r{/customers/}
          company = Company.first

          token = company.try!(:id)

          if company && route.path.include?(":location_id")
            token_2 = company.company_locations.first.try!(:id)
          end
        else
          ### SKIP - WITHOUT KNOWING A CORRECT TOKEN/ID WE CANNOT TEST THIS ROUTE
          next
        end

        if token.nil?
          puts "Token Not Found: #{route.path}"
          next
        elsif route.required_parts.count == 2 && token_2.nil?
          puts "Token Not Found: #{route.path}"
          next
        elsif token == false || route.required_parts.count > 2
          next
        end
      end

      ### NORMALIZE PATH
      if route.name.present?
        if token
          if token_2
            path = send("#{route.name}_path", token, token_2)
          else
            path = send("#{route.name}_path", token)
          end
        else
          path = send("#{route.name}_path")
        end
      else
        ### THIS WAY WORKS FOR ALL ROUTES
        path = route.path.split("(").first
      end


      ### GET ALL ALLOWED FORMATS FROM CONSTRAINTS
      formats = []

      if route.constraints[:format].blank?
        if path.include?(".")
          formats << path.split(".").last
        else
          formats << "html"
        end
      else
        if [String, Symbol].include?(route.constraints[:format].class)
          formats << route.constraints[:format]
        elsif route.constraints[:format].is_a?(Array)
          route.constraints[:format].each do |x|
            formats << x
          end
        end
      end

      ### ADD URLS TO TEST
      formats.each do |f|
        @scrubbed_routes << {
          method: method,
          path: path,
          format: f,
          route_object: route,
        }.with_indifferent_access
      end

      tested_routes_count += 1
    end

    puts "\nAll Routes Test: Testing #{tested_routes_count} of #{total_route_count} Total Routes (#{get_route_count} GET Routes)\n"
  end

  it "Test All Pages Not Signed In" do
    @scrubbed_routes.each do |h|
      begin
        ### Perform request
        send(h[:method], h[:path], params: {format: h[:format]})

        if h[:path].include?("/management")
          expect(response).to redirect_to(new_user_session_path)
        else
          expect(response).not_to redirect_to(@error_redirect_url)
          expect(response).not_to redirect_to(new_user_session_path)
        end
      rescue Exception => e
        if e.is_a?(RSpec::Expectations::ExpectationNotMetError)
          e.message << "\nFailed on #{h[:path]}, Method: #{h[:method]}, Format: #{h[:format]}, User: None"
        end

        raise e
      end
    end
  end

  it "Test All Languages" do
    sign_in(ADMIN_USER)

    SUPPORTED_LOCALE_TYPES.each do |locale|
      @scrubbed_routes.each do |h|
        begin
          ### Perform request
          send(h[:method], h[:path], params: {format: h[:format], locale: locale})

          expect(response).not_to redirect_to(@error_redirect_url)
        rescue Exception => e
          sign_out(ADMIN_USER)

          if e.is_a?(RSpec::Expectations::ExpectationNotMetError)
            e.message << "\nFailed on #{h[:path]}, Method: #{h[:method]}, Format: #{h[:format]}, User: #{user.email}, Locale: #{locale}"
          end

          raise e
        end
      end
    end

    sign_out(ADMIN_USER)
  end

  it "Test All User Roles" do
    [READ_USER, WRITE_USER, ACCOUNT_ADMIN_USER, ADMIN_USER].each do |user|
      sign_in(user)

      @scrubbed_routes.each do |h|
        begin
          ### Perform request
          send(h[:method], h[:path], params: {format: h[:format]})

          path = h[:path]

          if path.include?("/management/")
            if path.include?('/admin')
              if user.admin
                expect(response).not_to redirect_to(@error_redirect_url)
              else
                expect(response).to redirect_to(@error_redirect_url)
              end
            elsif path.include?('/account')
              if Ability.new(user).can?(:manage, :account)
                expect(response).not_to redirect_to(@error_redirect_url)
              else
                expect(response).to redirect_to(@error_redirect_url)
              end
            elsif READ_USER.id == user.id
              if["new", "edit", "update", "save", "delete", "destroy"].any?{|x| request.params[:action].include?(x) }
                expect(response).to redirect_to(@error_redirect_url)
              else
                expect(response).not_to redirect_to(@error_redirect_url)
              end
            elsif WRITE_USER.id == user.id
              if["imports"].any?{|x| h[:path].include?(x) }
                expect(response).to redirect_to(@error_redirect_url)
              else
                expect(response).not_to redirect_to(@error_redirect_url)
              end
            else
              expect(response).not_to redirect_to(@error_redirect_url)
            end
          else
            expect(response).not_to redirect_to(@error_redirect_url)
          end
        rescue Exception => e
          sign_out(user)

          if e.is_a?(RSpec::Expectations::ExpectationNotMetError)
            e.message << "\nFailed on #{h[:path]}, Method: #{h[:method]}, Format: #{h[:format]}, User: #{user.email}"
          end

          raise e
        end
      end
    end
  end

end
