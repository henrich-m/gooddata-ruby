# Copyright (c) 2010-2018 GoodData Corporation. All rights reserved.
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

require 'gooddata'

describe 'Kubernetes component LCM brick deployment' do
  before(:all) do
    @rest_client = ConnectionHelper.create_default_connection
    @project = @rest_client.create_project(
      title: 'Project for K8s LCM bricks end 2 end tests',
      auth_token: ConnectionHelper::SECRETS[:gd_project_token],
      environment: ProjectHelper::ENVIRONMENT
    )
    @options = { project: @project, client: @rest_client }

    component_name = ENV['LCM_BRICKS_COMPONENT_NAME']
    if component_name.nil?
      image_tag = ENV['LCM_BRICKS_IMAGE_TAG'] || 'M3'
      @component_name = "lcm-brick[#{image_tag}]-help"
    else
      @component_name = component_name
    end
    GoodData.logger.debug("Using component with name #{@component_name}")
  end

  after(:all) do
    @project.delete if @project
    @rest_client.disconnect
  end

  it 'deploys and run' do
    begin
      brick_component_data = {
        name: @component_name,
        type: 'LCM',
        component: {
          name: @component_name,
          version: '3'
        }
      }
      component_deployment = GoodData::Process.deploy_component brick_component_data, client: @rest_client, project: @project
      expect(component_deployment.name).to eq @component_name
      expect(component_deployment.type).to eq :lcm

      manual_schedule = component_deployment.create_manual_schedule

      execution_result = manual_schedule.execute

      expect(execution_result).to be_an_instance_of(GoodData::Execution)
      expect(execution_result.status).to eq(:ok)
    ensure
      component_deployment.delete if component_deployment
    end
  end
end
