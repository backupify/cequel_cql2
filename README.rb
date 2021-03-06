# # CequelCQL2 #
#
# CequelCQL2 is a
# [CQL](http://www.datastax.com/docs/1.0/references/cql/index#cql-commands)
# query builder and object-row mapper for
# [Cassandra](http://cassandra.apache.org/).
#
# The library consists of two layers. The lower CequelCQL2 layer is a lightweight
# CQL query builder, which uses chained scopes to construct CQL queries, execute
# them against your Cassandra instance, and return results in friendly form.
# The CequelCQL2::Model layer implements an object-row mapper on top of CequelCQL2,
# with full [ActiveModel](https://github.com/rails/rails/tree/master/activemodel)
# integration and an interface that conforms to established patterns for Ruby
# persistence layers (e.g. ActiveRecord).
#
# The lower CequelCQL2 layer is heavily inspired by the excellent
# [Sequel](http://sequel.rubyforge.org/) library; CequelCQL2::Model more closely
# follows the form of [ActiveRecord](http://ar.rubyonrails.org/).

# ## Installation ##

# To use only the lower-level CequelCQL2 query builder, just add the gem to your
# Gemfile.

gem 'cequel'

# For CequelCQL2::Model, instead require 'cequel/model'.

gem 'cequel', :require => 'cequel/model'

# ### Rails integration ###
#
# CequelCQL2 and CequelCQL2::Model do not require Rails, but if you are using Rails, you
# will need version 3.2+. CequelCQL2::Model will read from the configuration file
# `config/cequel.yml` if it is present. A simple example configuration would look
# like this.

development:
  host: '127.0.0.1:9160'
  keyspace: myapp_development

production:
  hosts:
    - 'cass1.myapp.biz:9160'
    - 'cass2.myapp.biz:9160'
    - 'cass3.myapp.biz:9160'
  keyspace: myapp_production
  thrift:
    retries: 10
    timeout: 15
    connect_timeout: 15

# ## CequelCQL2 Query Builder ##
#
# To connect to a keyspace, use `CequelCQL2.connect`:

cassandra = CequelCQL2.connect(
  :host => '127.0.0.1:9160',
  :keyspace => 'myapp_development'
)

# Column family handles are referenced like this.

posts = cassandra[:posts]

# ### Reading Data ###
#
# To select data, you can form a query using the familiar chained scope pattern.

posts = cassandra[:posts].select(:title).
  consistency(:quorum).
  where(:id => 1).
  limit(10)

titles = posts.map { |post| post[:title] }

# When working with wide rows, you often want to select a range of columns rather
# than a predefined set.

# Select columns 1-5
cassandra[:posts].select(1..5)

# Select columns 5 and up
cassandra[:posts].select(:from => 5)

# Select columns up to 5
cassandra[:posts].select(:to => 5)

# Select the first 8 columns (in natural order of column type)
cassandra[:posts].select(:first => 8)

# Select the last 6 columns
cassandra[:posts].select(:last => 6)

# Combine ranges and limits
cassandra[:posts].select(1..100, :first => 5)

# Or open-ended ranges and limits
cassandra[:posts].select(:first => 5, :from => 20)

# Data set scopes also support the `first` and `count` methods.

# #### Subqueries ####

# CequelCQL2 scopes support a subquery-like syntax, which can be used to populate
# the scope of an outer query with the results of an inner query:

cassandra[:blogs].where(:id => cassandra[:posts].select(:blog_id))

# This actually performs two queries to Cassandra, since CQL itself does not
# support subqueries.

# ### Writing data ###
#
# To insert data, use `insert`.

cassandra[:posts].insert(:id => 1, :title => 'My Post', :body => 'Some wisdom')

# You can control consistency, timestamp, and time to live by passing a second
# options hash to insert.

cassandra[:posts].insert(
  {:id => 1, :title => 'My Post', :body => 'Some wisdom'},
  :consistency => :quorum, :ttl => 10.minutes, :timestamp => 1.day.ago
)

# To update data, construct a scope and then call `update` with the columns to
# write:

cassandra[:posts].where(:id => [1, 2]).update(:title => 'My Post')

# To delete entire rows, call the `delete` method with no arguments.

cassandra[:posts].where(:id => [1, 2]).delete

# To delete certain columns from a row, pass those columns to `delete`.
cassandra[:posts].where(:id => [1, 2]).delete(:title)

# ## CequelCQL2::Model ##
#
# `CequelCQL2::Model` is a higher-level object-row mapper built on top of the
# low-level functionality described above. CequelCQL2 models are
# ActiveModel-compliant and generally follow ActiveRecord-like patterns.

# ### Defining a model ###
#
# CequelCQL2 models include the `CequelCQL2::Model` module; here's an example model
# definition that covers most of what's available.

class Post

  include CequelCQL2::Model
  include CequelCQL2::Model::Timestamps

  key :id, :uuid
  column :title, :text
  column :body, :text

  belongs_to :blog
  has_many :comments

  attr_accessible :title, :body

  validates :title, :body, :blog_id, :presence => true

  after_create :post_to_twitter

  default_scope limit(100)

  private

  def generate_key
    CassandraCQL::UUID.new
  end

end

# ### Working with models: The non-surprising parts ###
#
# Model behavior will be largely familiar to anyone who has worked with
# ActiveRecord or another ActiveRecord-inspired object mapper. All of these
# operations work pretty much exactly as you'd expect:

# Initialize a new instance
Post.new

# Initialize a new instance with some attributes
Post.new(:title => 'Hey')

# Initialize a new instance and set some properties
Post.new do |post|
  post.title = 'Hey'
end

# Create a new instance with attributes and save it
Post.create(:title => 'Hey')

# Create a new instance with attributes and save it violently
Post.create!(:title => 'Hey')

# Update an instance
post.title = 'New title'
post.save

# Destroy an instance
post.destroy

# Find an instance by key
Post.find(uuid)

# Find an instance by magic
Post.find_by_blog_id(blog_id)

# Find lots of instances by magic
Post.find_all_by_blog_id(blog_id)

# Find or initialize an instance by magic
Post.find_or_initialize_by_title('My Post')

# Find or initialize an instance by magic with some extra attributes
Post.find_or_initialize_by_title(:title => 'My Post', :body => 'Read more')

# Of course, find_or_create_by works too
Post.find_or_create_by_title('My Post')

# Query by scopes
Post.select(:title).where(:id => uuid).first

# Query by secondary indexes
Post.select(:title).where(:blog_id => blog_uuid).map { |post| post.title }

# This will execute three queries, because CQL secondary indexes don't play nice
# with IN restrictions. But it'll work.
Post.select(:title).
  where(:blog_id => [blog_id1, blog_id2, blog_id3]).
  map { |post| post.title }

# ### Working with models: The surprising parts ###
#
# CQL is designed to be immediately familiar to those of us who are used to
# working with SQL, which is all of us. CequelCQL2 advances this spirit by providing
# an ActiveRecord-like mapping for CQL. However, Cassandra is very much not a
# relational database, so some behaviors can come as a surprise. Here's an
# overview.

# #### Upserts ####
#
# CQL provides `INSERT` and `UPDATE` statements that look more or less exactly
# like their SQL equivalents. However, these statements do exactly the same thing,
# just with different syntax. What they do is to write values into
# columns at a key. So these two CequelCQL2 statements have identical behavior.

# Both of these statements instruct Cassandra to set the value of the `title`
# column in row 1 to "Post".

cassandra[:posts].insert(:id => 1, :title => 'Post')
cassandra[:posts].where(:id => 1).update(:title => 'Post')

# CequelCQL2::Model uses the `INSERT` statement to persist objects that have been
# newly initialized in memory, and the `UPDATE` statement to save changes to
# objects that were loaded out of Cassandra. There is no particular reason for
# this; it just feels right. But beware: you may think you're inserting a new row
# when you're actually overwriting data that already exists in that row

# I'm just creating a post here.
post1 = Post.new(:id => 1, :title => 'My Post', :blog_id => 1)
post1.save!

# And let's make another one
post2 = Post.new(:id => 1, :title => 'Another Post')
post2.save!

# Living in a relational world, we'd expect the second statement to throw an
# error because row 1 already exists. But not Cassandra: the above code will just
# overwrite the `title` in that row. Note that the `blog_id` will not be touched;
# upserts only work on the columns that are given.

# #### Dirty Updates ####
#
# CequelCQL2::Model includes ActiveModel's dirty tracking. When you save a persisted
# model, only columns that have changed in memory will be included in the `UPDATE`
# statement.
#
# Note that updating a model may generate two CQL statements. This is because
# Cassandra does not have a concept of null values; a column either has data or it
# doesn't. So, if you change an attribute of your model from a non-nil value to
# `nil`, CequelCQL2::Model will issue a DELETE statement just for the column(s) in
# question.
#
# If you don't change anything, calling '#save' on a persisted model is a no-op.

# #### Pondering Existence ####
#
# In a relational database, there is a well-defined concept of existence; there is
# either a row for a given primary key or there isn't. It's possible to have a row
# consisting of only a primary key, and that row still "exists" in a meaningful
# way.
#
# Cassandra works more like a key-value store: each key either has data, or it
# doesn't, but beyond that there is no explicit concept of a key or row existing.
# Semantically, we can think of a Cassandra row existing if it has data in any
# column. But that's a concept that only exists in our minds (and in CequelCQL2), not
# in the database itself. Consider the following:

# This outputs `{'id' => 1}`
cassandra[:posts].where(:id => 1).first

# The above behavior will hold even if no data has ever been written to key 1. It
# will also happen if key 1 existed at one time and then was deleted.
#
# This behavior is complicated by "range ghosts". Range ghosts happen when you
# delete all the data from a row. You'll only see them when performing unlimited
# or key-range queries, and they go away after a while. There's a good reason for
# this, but it's confusing. For instance, let's say in the entire history of our
# database, all we've done is create post 1, and then delete it. Let's see what
# happens when we select all posts.

# This outputs `[{'id' => 1}]`
cassandra[:posts].to_a

# That's a range ghost: it's a result row consisting of only the key.
#
# CequelCQL2::Model makes explicit our implicit semantic idea that rows only exist if
# they have data in a column (not counting the key, which isn't really a column).
# So any time CequelCQL2::Model sees a row that's either empty or only has a key, it
# drops it. You'll never get back a model instance containing data in no non-key
# columns.
#
# If you perform a `#find` and get back no non-key data, the library will raise
# `CequelCQL2::Model::RecordNotFound`.
#
# This behavior can especially trip you up when you are selecting specific
# columns. For instance, let's say post 1 only has data in the `title` field.

# This gives me back a nice post object.
Post.find(uuid)

# This aises `CequelCQL2::Model::RecordNotFound`, because there was no data in the
# row.
Post.select(:blog_id).find(uuid)

# This fails fast before any interaction with Cassandra: this is a meaningless
# query.
Post.select(:id).find(uuid)

# #### Key and Secondary Index Selection ####
#
# CQL gives you a few ways to filter the rows you want returned in a query:
#
# * A single key
# * A list of keys
# * A range of keys
# * A secondary index
# * A secondary index combined with one or more filters
#
# That's it. You can't filter by:
#
# * A non-indexed column
# * A key/list of keys combined with a secondary index
# * A key/list of keys combined with a filter

# So let's say our `posts` column family has a secondary index on `blog_id` and
# nothing else. These will work.

Post.find(uuid)
Post.find([uuid1, uuid2])
Post.where('id > ?', uuid)
Post.find_by_blog_id(blog_id)
Post.where(:blog_id => blog_id).where('created_at > ?', 1.day.ago)

# These won't work.

Post.where('created_at > ?', 1.day.ago)
Post.where(:id => uuid, :blog_id => blog_id)
Post.where(:id => uuid).where('created_at > ?', 1.day.ago)

# ## CequelCQL2::Model::Dictionary ##
#
# The functionality of the CequelCQL2::Model class maps the "skinny row" style of
# column family structure: each row has a small set of predefined columns, with
# heterogeneous value types. However, the "wide row" structure will also play an
# important role in most Cassandra schemas (if this is news to you, I recommend
# reading
# [this article](http://www.rackspace.com/blog/cassandra-by-example/?072d7a80)).
# CequelCQL2 provides the `CequelCQL2::Model::Dictionary` class, which abstracts wide rows
# as a dictionary object, behaving much like a Hash.

# Applications should define subclasses of the `Dictionary` class to interact with
# data in a certain column family. For instance, let's say I've got a `blog_posts`
# column family.

class BlogPosts < CequelCQL2::Model::Dictionary

  key :blog_id, :uuid
  maps :uuid => :text

  private

  def serialize_value(column, value)
    value.to_json
  end

  def deserialize_value(column, value)
    JSON.parse(value)
  end

end

# In this case, your column family has a key with alias `blog_id` of type `uuid`,
# comparator of type `uuid`, and default validation of type `text`. The
# `serialize_value` and `deserialize_value` methods are optional, but aid with the
# common pattern of storing blobs of JSON, msgpack, etc. in wide-row values.

# ### Reading data ###

# To grab a handle to a dictionary, use the bracket operator.
posts = BlogPosts[blog_id]

# This does not perform any queries against Cassandra; it just gives you an object
# pointing at a particular row. By default, reads are lazy.

post_json = posts[post_id]

# This will select a single column from the `blog_posts` column family and return
# its deserialized value. The value is not retained in the dictionary itself.

# If you want to work with the entire contents of the wide row in memory, use the
# `#load` method.

posts = BlogPosts[blog_id]
posts.load # loads all values into memory
posts[post_id] # doesn't do an additional query

# Dictionaries expose the major read methods of the Hash interface:

posts.each_pair { |column, value| do_something(column, value) }
posts.keys
posts.values
posts.map { |column, value| transform(column, value) }
posts.slice(uuid1, uuid2, uuid3) # returns a Hash

# All of the above methods will read from Cassandra if the dictionary is unloaded,
# and read from memory if the dictionary is loaded. Note that for methods that
# read all columns out of the database, columns will be loaded in batches of 1000
# by default.

# ### Writing Data ###
#
# Modifying data is, unsurprisingly, done using the `[]=` operator. When you call
# `#save`, any keys that you have modified with the `[]=` operator will be
# persisted to Cassandra. The dictionary does not use true dirty tracking, in the
# sense that it will write an attribute even if you set it to the same value it
# had previously.
#
# Write behavior is the same regardless of loaded status.

# ## Road Map ##
#
# As mentioned previously in this document, there are considerable differences
# between modeling data in Cassandra and modeling data in a relational database,
# despite their superficial similarities. In Cassandra, wide rows are an important
# part of schema design; "existence" is a fuzzy concept; denormalization is often
# a good idea; secondary indexes are of limited use. Broadly, the goal for future
# versions of CequelCQL2 is to provide a more robust abstraction and tool kit for
# modeling data in Cassandra the right way. Specifically, here are some things to
# look forward to in future CequelCQL2 versions:
#
# * Support for auto-migrations by introspecting the schema and making
#   modifications to fit the model-defined schema.
# * One-one relationships using multiple classes per column family.
# * Additional wide-row data structures: lists and sets.
# * Tighter integration between CequelCQL2::Model and CequelCQL2::Model::Dictionary;
#   `references_many` associations.
# * Bidirectional associations.
# * Using defined column types to ensure objects passed to CassandraCQL layer are
#   of the correct type/encoding.

# ## Getting Help ##
#
# Send me an email at mat@brewster.com; find me on Freenode on #cassandra (I'm
# outoftime); or file an issue on GitHub.

# ## License ##
#
# CequelCQL2 is distributed under the MIT license. See the attached LICENSE for all
# the sordid details.
