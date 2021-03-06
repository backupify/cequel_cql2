require File.expand_path('../../environment', __FILE__)

Dir.glob(File.expand_path('../../support/**/*.rb', __FILE__)).each do |file|
  require file
end
Dir.glob(File.expand_path('../../shared/**/*.rb', __FILE__)).each do |file|
  require file
end

RSpec.configure do |config|
  config.include(CequelCQL2::SpecSupport::Helpers)
end
