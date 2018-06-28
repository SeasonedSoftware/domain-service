class BaseService
  def initialize(context, input)
    raise 'missing DATABASE_URL env' if ENV['DATABASE_URL'].nil?
    @pgconn = PG.connect(ENV['DATABASE_URL'])
    @context = context
    @input = input
  end

  protected

  def input_action
    @input_action ||= @input['action']
  end

  def call_id
    @call_id ||= @context.call_id
  end
end
