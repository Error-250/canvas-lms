#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require File.expand_path(File.dirname(__FILE__) + '/../api_spec_helper')

describe "Collections API", :type => :integration do
  before do
    user_with_pseudonym
    @collections_path = "/api/v1/users/#{@user.id}/collections"
    @collections_path_options = { :controller => "collections", :action => "index", :format => "json", :user_id => @user.to_param }
    @c1 = @user.collections.create!(:name => 'test1', :visibility => 'private')
    @c2 = @user.collections.create!(:name => 'test2', :visibility => 'public')
    @c1_json =
      {
        'id' => @c1.id,
        'name' => @c1.name,
        'visibility' => 'private',
      }
    @c2_json = 
      {
        'id' => @c2.id,
        'name' => @c2.name,
        'visibility' => 'public',
      }
  end

  context "a user's own collections" do
    it "should allow retrieving a paginated collection list" do
      json = api_call(:get, @collections_path, @collections_path_options)
      response['Link'].should be_present
      json.should == [ @c2_json, @c1_json ]
    end

    it "should allow retrieving a private collection" do
      json = api_call(:get, @collections_path + "/#{@c1.id}", @collections_path_options.merge(:collection_id => @c1.to_param, :action => "show"))
      json.should == @c1_json
    end

    it "should allow creating a collection" do
      json = api_call(:post, @collections_path, @collections_path_options.merge(:action => "create"), {
        :name => "test3",
        :visibility => 'public',
      })
      @c3 = Collection.last(:order => :id)
      json.should == {
        'id' => @c3.id,
        'name' => 'test3',
        'visibility' => 'public',
      }
    end

    it "should allow updating a collection" do
      json = api_call(:put, @collections_path + "/#{@c1.id}", @collections_path_options.merge(:collection_id => @c1.to_param, :action => "update"), {
        :name => "test1 edited",
      })
      json.should == @c1_json.merge('name' => 'test1 edited')
      @c1.reload.name.should == "test1 edited"
    end

    it "should not allow changing visibility" do
      json = api_call(:put, @collections_path + "/#{@c1.id}", @collections_path_options.merge(:collection_id => @c1.to_param, :action => "update"), {
        :name => "test1 edited",
        :visibility => "public",
      }, {}, :expected_status => 400)
      @c1.name.should == "test1"
      @c1.visibility.should == "private"
    end

    it "should allow deleting a collection" do
      json = api_call(:delete, @collections_path + "/#{@c1.id}", @collections_path_options.merge(:collection_id => @c1.to_param, :action => "destroy"))
      @c1.reload.state.should == :deleted
    end

    context "deleted collection" do
      before do
        @c1.destroy
      end

      it "should not return in list" do
        json = api_call(:get, @collections_path, @collections_path_options)
        json.should == [ @c2_json ]
      end

      it "should not allow getting" do
        json = api_call(:get, @collections_path + "/#{@c1.id}", @collections_path_options.merge(:collection_id => @c1.to_param, :action => "show"), {}, {}, :expected_status => 404)
      end
    end
  end

  context "another user's collections" do
    before do
      user_with_pseudonym
    end

    it "should only list public collections" do
      json = api_call(:get, @collections_path, @collections_path_options)
      response['Link'].should be_present
      json.should == [ @c2_json ]
    end

    it "should allow getting a public collection" do
      json = api_call(:get, @collections_path + "/#{@c2.id}", @collections_path_options.merge(:collection_id => @c2.to_param, :action => "show"))
      json.should == @c2_json
    end

    it "should not allow getting a private collection" do
      json = api_call(:get, @collections_path + "/#{@c1.id}", @collections_path_options.merge(:collection_id => @c1.to_param, :action => "show"), {}, {}, :expected_status => 401)
      json['message'].should match /not authorized/
    end

    it "should not allow updating a collection" do
      json = api_call(:put, @collections_path + "/#{@c2.id}", @collections_path_options.merge(:collection_id => @c2.to_param, :action => "update"), {
        :name => "test2 edited",
      }, {}, :expected_status => 401)
      @c2.reload.name.should == "test2"
    end

    it "should not allow deleting a collection" do
      json = api_call(:delete, @collections_path + "/#{@c2.id}", @collections_path_options.merge(:collection_id => @c2.to_param, :action => "destroy"), {}, {}, :expected_status => 401)
      @c2.reload.should be_active
    end
  end

  describe "Collection Items" do
    before do
      @i1 = collection_item_model(:description => "item 1", :user => @c1.context, :collection => @c1, :collection_item_data => collection_item_data_model(:link_url => "http://www.example.com/one"))
      @i2 = collection_item_model(:description => "item 2", :user => @c1.context, :collection => @c1, :collection_item_data => collection_item_data_model(:link_url => "http://www.example.com/two"))
      @i3 = collection_item_model(:description => "item 3", :user => @c2.context, :collection => @c2, :collection_item_data => collection_item_data_model(:link_url => "http://www.example.com/three"))
      @items1_path = "/api/v1/collections/#{@c1.id}/items"
      @items2_path = "/api/v1/collections/#{@c2.id}/items"
      @items1_path_options = { :controller => "collection_items", :action => "index", :format => "json", :collection_id => @c1.to_param }
      @items2_path_options = { :controller => "collection_items", :action => "index", :format => "json", :collection_id => @c2.to_param }

      @user1 = @user
      user_with_pseudonym
      @user2 = @user
      @user = @user1
      @c3 = @user2.collections.create!(:name => 'user2', :visibility => 'public')
      @i4 = collection_item_model(:description => "cloned item 3", :user => @c3.context, :collection => @c3, :collection_item_data => @i3.collection_item_data); @i3.reload
      @items3_path = "/api/v1/collections/#{@c3.id}/items"
      @items3_path_options = { :controller => "collection_items", :action => "index", :format => "json", :collection_id => @c3.to_param }
    end

    def item_json(item, upvoted_by_user = false)
      {
        'id' => item.id,
        'collection_id' => item.collection_id,
        'item_type' => item.collection_item_data.item_type,
        'link_url' => item.collection_item_data.link_url,
        'post_count' => item.collection_item_data.post_count,
        'upvote_count' => item.collection_item_data.upvote_count,
        'upvoted_by_user' => upvoted_by_user,
        'root_item_id' => item.collection_item_data.root_item_id,
        'image_url' => item.data.image_attachment && "http://www.example.com/images/thumbnails/#{item.data.image_attachment.id}/#{item.data.image_attachment.uuid}?size=640x%3E",
        'image_pending' => item.data.image_pending,
        'html_preview' => item.data.html_preview,
        'description' => item.description,
        'url' => "http://www.example.com/api/v1/collections/items/#{item.id}",
      }
    end

    it "should allow retrieving a pagniated item list from a private collection" do
      json = api_call(:get, @items1_path, @items1_path_options)
      response['Link'].should be_present
      json.should == [ item_json(@i2), item_json(@i1) ]
    end

    describe "item creation" do
      it "should allow creating from a http url" do
        json = api_call(:post, @items1_path, @items1_path_options.merge(:action => "create"), { :link_url => "http://www.example.com/a/b/c", :description => 'new item' })
        new_item = @c1.collection_items.last(:order => :id)
        new_item.collection_item_data.link_url.should == "http://www.example.com/a/b/c"
        new_item.user.should == @user
      end

      it "should allow cloning an existing item" do
        json = api_call(:post, @items1_path, @items1_path_options.merge(:action => "create"), { :link_url => "http://localhost/api/v1/collections/items/#{@i3.id}", :description => 'cloned' })
        json['post_count'].should == 3
        new_item = @c1.collection_items.last(:order => :id)
        new_item.collection_item_data.should == @i3.collection_item_data
        new_item.user.should == @user
      end

      it "should not allow cloning an item the user can't access" do
        @user = @user2
        expect {
          json = api_call(:post, @items3_path, @items3_path_options.merge(:action => "create"), { :link_url => "http://localhost/api/v1/collections/items/#{@i1.id}", :description => 'cloned' }, {}, :expected_status => 401)
        }.to change(CollectionItem, :count).by(0)
      end

      it "should reject non-http urls" do
        expect {
          json = api_call(:post, @items1_path, @items1_path_options.merge(:action => "create"), { :link_url => "javascript:alert(1)", :description => 'new item' }, {}, :expected_status => 400)
        }.to change(CollectionItem, :count).by(0)
      end

      describe "images" do
        it "should take a snapshot of the link url if no image is provided and there is no embedly image" do
          json = api_call(:post, @items1_path, @items1_path_options.merge(:action => "create"), { :link_url => "http://www.example.com/a/b/c", :description => 'new item' })
          @item = CollectionItem.find(json['id'])
          @item.data.image_pending.should == true
          @att = Attachment.new(:uploaded_data => stub_png_data)
          CutyCapt.expects(:snapshot_attachment_for_url).with(@item.data.link_url).returns(@att)
          run_job()

          @att.reload.context.should == Account.default

          @item.reload.data.image_pending.should == false
          @item.data.image_attachment.should == @att

          json = api_call(:get, "/api/v1/collections/items/#{@item.id}", { :controller => "collection_items", :item_id => @item.to_param, :action => "show", :format => "json" })
          json['image_pending'].should == false
          json['image_url'].should == "http://www.example.com/images/thumbnails/#{@att.id}/#{@att.uuid}?size=640x%3E"
        end

        it "should clone and use the image if provided" do
          json = api_call(:post, @items1_path, @items1_path_options.merge(:action => "create"), { :link_url => "http://www.example.com/a/b/c", :image_url => "http://www.example.com/my/image.png", :description => 'new item' })
          @item = CollectionItem.find(json['id'])
          @item.data.image_pending.should == true
          http_res = mock('Net::HTTPOK', :body => File.read(Rails.root+"public/images/cancel.png"), :code => 200)
          Canvas::HTTP.expects(:get).with("http://www.example.com/my/image.png").returns(http_res)
          run_job()

          @item.reload.data.image_pending.should == false
          @att = @item.data.image_attachment
          @att.should be_present
          @att.context.should == Account.default

          json = api_call(:get, "/api/v1/collections/items/#{@item.id}", { :controller => "collection_items", :item_id => @item.to_param, :action => "show", :format => "json" })
          json['image_pending'].should == false
          json['image_url'].should == "http://www.example.com/images/thumbnails/#{@att.id}/#{@att.uuid}?size=640x%3E"
        end

        it "should use the embedly image if no image is provided" do
          json = api_call(:post, @items1_path, @items1_path_options.merge(:action => "create"), { :link_url => "http://www.example.com/a/b/c", :description => 'new item' })
          @item = CollectionItem.find(json['id'])
          @item.data.image_pending.should == true
          Canvas::Embedly.any_instance.expects(:get_embedly_data).with("http://www.example.com/a/b/c").returns(stub_everything('embedly api', :type => 'test', :images => [{'url' => 'http://www.example.com/image1'}], :html => "<iframe>test</iframe>"))
          http_res = mock('Net::HTTPOK', :body => File.read(Rails.root+"public/images/cancel.png"), :code => 200)
          Canvas::HTTP.expects(:get).with("http://www.example.com/image1").returns(http_res)
          run_job()

          @item.reload.data.image_pending.should == false
          @att = @item.data.image_attachment
          @att.should be_present
          @att.context.should == Account.default

          @item.data.html_preview.should == "<iframe>test</iframe>"

          json = api_call(:get, "/api/v1/collections/items/#{@item.id}", { :controller => "collection_items", :item_id => @item.to_param, :action => "show", :format => "json" })
          json['image_pending'].should == false
          json['image_url'].should == "http://www.example.com/images/thumbnails/#{@att.id}/#{@att.uuid}?size=640x%3E"
        end
      end
    end

    it "should allow editing mutable fields" do
      json = api_call(:put, "/api/v1/collections/items/#{@i1.id}", { :controller => "collection_items", :item_id => @i1.to_param, :action => "update", :format => "json" }, { :description => "modified", :link_url => 'cant change', :item_type => 'cant change', :image_url => "http://www.example.com/cant_change" })
      json.should == item_json(@i1.reload)
      @i1.description.should == "modified"
      @i1.collection_item_data.item_type.should == "url"
      @i1.data.image_pending.should == false
    end

    it "should allow deleting an owned item" do
      json = api_call(:delete, "/api/v1/collections/items/#{@i1.id}", { :controller => "collection_items", :item_id => @i1.to_param, :action => "destroy", :format => "json" })
      @i1.reload.state.should == :deleted
    end

    it "should not allow getting from a deleted collection" do
      @i1.collection.destroy
      # deleting the collection doesn't mark all the items as deleted, though
      # they can't be retrieved through the api
      # this makes undeleting work better
      @i1.reload.should be_active
      json = api_call(:get, "/api/v1/collections/items/#{@i1.id}", { :controller => "collection_items", :item_id => @i1.to_param, :action => "show", :format => "json" }, {}, {}, :expected_status => 404)
    end

    context "deleted item" do
      before do
        @i1.destroy
      end

      it "should not return in the list" do
        json = api_call(:get, @items1_path, @items1_path_options)
        json.should == [ item_json(@i2) ]
      end

      it "should not allow getting" do
        json = api_call(:get, "/api/v1/collections/items/#{@i1.id}", { :controller => "collection_items", :item_id => @i1.to_param, :action => "show", :format => "json" }, {}, {}, :expected_status => 404)
      end
    end

    context "another user's collections" do
      before do
        user_with_pseudonym
      end

      it "should not allow listing from a private collection" do
        json = api_call(:get, @items1_path, @items1_path_options, {}, {}, :expected_status => 401)
      end

      it "should allow listing a public collection" do
        json = api_call(:get, @items2_path, @items2_path_options)
        response['Link'].should be_present
        json.should == [ item_json(@i3) ]
      end
    end

    context "upvoting" do
      it "should allow upvoting an item" do
        @user = @user2
        json = api_call(:put, "/api/v1/collections/items/#{@i3.id}/upvote", { :controller => "collection_items", :action => "upvote", :item_id => @i3.to_param, :format => "json" })
        json.slice('item_id', 'root_item_id', 'user_id').should == {
          'item_id' => @i3.id,
          'root_item_id' => @i3.id,
          'user_id' => @user.id,
        }
        @i3.reload.collection_item_data.upvote_count.should == 1

        # upvoting again is a no-op
        json = api_call(:put, "/api/v1/collections/items/#{@i3.id}/upvote", { :controller => "collection_items", :action => "upvote", :item_id => @i3.to_param, :format => "json" })
        json.slice('item_id', 'root_item_id', 'user_id').should == {
          'item_id' => @i3.id,
          'root_item_id' => @i3.id,
          'user_id' => @user.id,
        }
        @i3.reload.collection_item_data.upvote_count.should == 1
      end

      it "should not allow upvoting a non-visible item" do
        @user = @user2
        json = api_call(:put, "/api/v1/collections/items/#{@i1.id}/upvote", { :controller => "collection_items", :action => "upvote", :item_id => @i1.to_param, :format => "json" }, {}, {}, :expected_status => 401)
        @i1.reload.collection_item_data.upvote_count.should == 0
      end
    end

    context "de-upvoting" do
      before do
        @user = @user2
      end

      it "should allow removing an upvote" do
        @i3.collection_item_data.collection_item_upvotes.create!(:user => @user)
        @i3.reload.collection_item_data.upvote_count.should == 1
        json = api_call(:delete, "/api/v1/collections/items/#{@i3.id}/upvote", { :controller => "collection_items", :action => "remove_upvote", :item_id => @i3.to_param, :format => "json" })
        @i3.reload.collection_item_data.upvote_count.should == 0
      end

      it "should ignore if the user hasn't upvoted the item" do
        json = api_call(:delete, "/api/v1/collections/items/#{@i3.id}/upvote", { :controller => "collection_items", :action => "remove_upvote", :item_id => @i3.to_param, :format => "json" })
      end
    end
  end
end
