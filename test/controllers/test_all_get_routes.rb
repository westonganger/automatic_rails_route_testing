### This is a decent starting point to testing for general exceptions on your views

class TestAllGetRoutes < ActionController::TestCase

  def setup
    @all_app_routes = Rails.application.routes.routes.map{|x| ActionDispatch::Routing::RouteWrapper.new(x) }.reject(&:internal?)

    @all_get_routes = @all_app_routes.select{|x| x.verb.blank? || x.verb == "GET" }

    @scrubbed_get_paths = []

    @all_get_routes.each do |route| 
      path = route.path.split("(").first

      if constraints[:format].present? && [String, Symbol].include?(route.constraints.format.class) && constraints[:format] != "html"
        path << ".#{constraints[:format]}"
      end

      @scrubbed_get_paths << path
    end
  end

  def teardown
  end

  def test_admin
    ### Test admin because they should have access to all routes

    @user = User.admin_users.first

    sign_in @user

    @scrubbed_get_paths.each do |route|
      get(path)

      if response.status == 302
        follow_redirect!
      end

      assert_equal 200, response.status
    end
  end

  def test_signed_out
    ### Test signed out to review fully un-authenticated pages
    
    @scrubbed_get_paths.each do |route|
      get(path)

      if response.status == 200
        unauthenticated << path
      end

      assert_not 404, response.status
      assert_not 500, response.status
    end

    File.open("test/unauthenticated_routes.txt", "wb") do |f|
      unauthenticted.each do |path|
        f.write "#{path}\n"
      end
    end

  end

end
