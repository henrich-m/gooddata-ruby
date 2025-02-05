require_relative 'support/configuration_helper'
require_relative 'support/project_helper'
require_relative 'support/connection_helper'
require_relative 'support/lcm_helper'
require 'gooddata_datawarehouse' unless GoodData::Environment::VCR_ON

def create_suffix
  hostname = Socket.gethostname
  timestamp = DateTime.now.strftime('%Y%m%d%H%M%S')
  suffix = "#{hostname}_#{timestamp}"
  segment_name_forbidden_chars = /[^a-zA-Z0-9_\\-]+/
  suffix.scan(segment_name_forbidden_chars).each do |forbidden_characters|
    suffix.gsub!(forbidden_characters, '_')
  end
  suffix
end

def create_workspace_csv(workspaces, client_id_column)
  temp_file = Tempfile.new('workspace_csv')
  headers = [client_id_column, 'segment_id', 'project_title']

  CSV.open(temp_file, 'w', write_headers: true, headers: headers) do |csv|
    workspaces.each do |workspace|
      csv << [workspace[:client_id],
              workspace[:segment_id],
              workspace[:title]]
    end
  end
  temp_file
end

shared_context 'lcm bricks' do |opts = {}|
  before(:all) do
    @config = {
      verify_ssl: false,
      environment: 'TESTING',
      master_prefix: 'Insurance Demo Master'
    }
    @config.merge!(LcmConnectionHelper.environment)
    @config[:ads_client] = {
      username: @config[:username],
      password: @config[:password]
    }
    connection_parameters = {
      username: @config[:username],
      password: @config[:password],
      server: "https://#{@config[:dev_server]}",
      verify_ssl: false
    }
    @rest_client = GoodData.connect(connection_parameters)
    @ads = ConfigurationHelper.create_development_datawarehouse(client: @rest_client,
                                                                title: 'Development ADS',
                                                                auth_token: @config[:vertica_dev_token])
    @config[:ads_client][:jdbc_url] = @ads.data['connectionUrl']

    @ads_client = GoodData::Datawarehouse.new(
      @config[:ads_client][:username],
      @config[:ads_client][:password],
      @config[:ads_client][:ads_id],
      jdbc_url: @ads.data['connectionUrl']
    )

    @release_table_name = 'LCM_RELEASE'
    LcmHelper.create_release_table(@release_table_name, @ads_client)
    @workspace_table_name = 'LCM_WORKSPACE'
    LcmHelper.create_workspace_table(
      @workspace_table_name,
      @ads_client,
      Support::CUSTOM_CLIENT_ID_COLUMN
    )

    $reuse_project = ENV['REUSE_PROJECT']

    project_helper = ConfigurationHelper.ensure_development_project(
      client: @rest_client,
      title: 'LCM spec Development Project',
      auth_token: @config[:dev_token],
      environment: @config[:environment],
      ads: @ads
    )
    project_helper.deploy_processes(@ads) unless $reuse_project

    @project = project_helper.project

    label = @project.labels.first
    @project.create_variable(title: 'uaaa', attribute: label.attribute).save unless $reuse_project
    label.meta['deprecated'] = 1
    label.save

    prod_connection_parameters = {
      username: @config[:username],
      password: @config[:password],
      server: "https://#{@config[:prod_server]}",
      verify_ssl: false
    }
    @prod_rest_client = GoodData.connect(prod_connection_parameters)
    @prod_ads = ConfigurationHelper.create_development_datawarehouse(client: @prod_rest_client,
                                                                     title: 'Production ADS',
                                                                     auth_token: @config[:vertica_prod_token])
    unless GoodData::Environment::VCR_ON
      @prod_output_stage_project = ConfigurationHelper.create_output_stage_project(
        @prod_rest_client,
        @suffix,
        @prod_ads,
        @config[:prod_token],
        @config[:environment]
      )
      production_output_stage_uri = @prod_output_stage_project.add.output_stage.data['schema']
    end

    segments = (%w(BASIC PREMIUM) * ($segments_multiplier || 1)).map.with_index do |segment, i|
      data = {
        segment_id: "LCM_SPEC_#{segment}_#{i}",
        development_pid: @project.obj_id,
        driver: segment == 'PREMIUM' ? 'vertica' : 'pg',
        master_name: "LCM spec master project (#{segment} #{i}) " + '##{version}' # rubocop:disable Lint/InterpolationCheck
      }

      unless GoodData::Environment::VCR_ON
        data[:ads_output_stage_uri] = production_output_stage_uri
        data[:ads_output_stage_prefix] = Support::OUTPUT_STAGE_PREFIX
      end
      data
    end
    segments_filter = segments.map { |s| s[:segment_id] }

    @workspaces = (segments * ($workspaces_multiplier || 2)).map.with_index do |segment, i|
      {
        client_id: "LCM_SPEC_CLIENT_#{i}",
        segment_id: segment[:segment_id],
        title: "LCM SPEC PROJECT #{i}"
      }
    end

    conflicting_client_id = 'LCM_SPEC_CLIENT_WITH_CONFLICTING_LDM_CHANGES'
    @workspaces << {
      client_id: conflicting_client_id,
      segment_id: segments.first[:segment_id],
      title: 'LCM spec Client With Conflicting LDM Changes'
    }

    s3_endpoint = 'http://localstack:4572'
    workspace_csv = LcmHelper.create_workspace_csv(
      @workspaces,
      Support::CUSTOM_CLIENT_ID_COLUMN
    )
    s3 = Aws::S3::Resource.new(access_key_id: 'foo',
                               secret_access_key: 'foo',
                               endpoint: s3_endpoint,
                               region: 'us-west-2',
                               force_path_style: true)

    bucket_name = 'testbucket'
    bucket = s3.bucket(bucket_name)
    bucket = s3.create_bucket(bucket: bucket_name) unless bucket.exists?
    obj = bucket.object(@workspace_table_name)
    obj.upload_file(Pathname.new(workspace_csv))

    if GoodData::Environment::VCR_ON && GoodData::Helpers::VcrConfigurer.vcr_cassette_playing?
      @data_product_id = GoodData::Helpers::VcrConfigurer::VCR_DATAPRODUCT_ID
    else
      @data_product_id = 'LCM_DATA_PRODUCT_' + GoodData::Environment::RANDOM_STRING
    end


    @test_context = {
      release_table_name: @release_table_name,
      workspace_table_name: @workspace_table_name,
      config: @config,
      ads_client: @ads_client,
      jdbc_url: @ads.data['connectionUrl'],
      development_pid: @project.obj_id,
      segments: segments.to_json,
      segments_filter: segments_filter.to_json,
      data_product: @data_product_id,
      input_source_type: 's3',
      s3_bucket: bucket_name,
      s3_endpoint: s3_endpoint,
      custom_client_id_column: Support::CUSTOM_CLIENT_ID_COLUMN,
      transfer_all: true,
      conflicting_client_id: conflicting_client_id,
      schedule_additional_hidden_params: (opts[:schedule_additional_hidden_params] || {}).to_json,
      process_additional_hidden_params: (opts[:process_additional_hidden_params] || {}).to_json
    }
  end

  after(:each) do
    $SCRIPT_PARAMS = nil
  end

  after(:all) do
    projects_to_delete = $master_projects + $client_projects

    projects_to_delete += [@prod_output_stage_project] unless GoodData::Environment::VCR_ON
    projects_to_delete += [@project] unless ENV['REUSE_PROJECT']

    projects_to_delete.each do |project|
      begin
        # We need to delete the output stage explicitly
        # because of https://jira.intgdc.com/browse/DSS-2967
        project.add && project.add.output_stage && project.add.output_stage.delete
      rescue StandardError => e
        GoodData.logger.warn("Failed to delete output stage. #{e}")
        GoodData.logger.warn("Backtrace:\n#{e.backtrace.join("\n")}")
      end

      begin
        GoodData.logger.info("Deleting project \"#{project.title}\" with ID #{project.pid}")
        project.delete unless project.deleted?
      rescue StandardError => e
        GoodData.logger.warn("Failed to delete project #{project.title}. #{e}")
        GoodData.logger.warn("Backtrace:\n#{e.backtrace.join("\n")}")
      end
    end

    ConfigurationHelper.delete_datawarehouse(@prod_ads)
    ConfigurationHelper.delete_datawarehouse(@ads)

    begin
      GoodData.logger.info("Deleting segments")
      domain = @rest_client.domain(@config[:prod_organization])
      data_product = domain.data_products(@data_product_id)
      data_product.delete(force: true)
    rescue StandardError => e
      GoodData.logger.warn("Failed to delete segments. #{e}")
      GoodData.logger.warn("Backtrace:\n#{e.backtrace.join("\n")}")
    end

    @rest_client.disconnect if @rest_client
    @prod_rest_client.disconnect if @rest_client
  end
end
