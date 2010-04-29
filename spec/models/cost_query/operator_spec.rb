require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe CostQuery do
  before { @query = CostQuery.new }

  fixtures :users
  fixtures :cost_types
  fixtures :cost_entries
  fixtures :rates
  fixtures :projects
  fixtures :issues
  fixtures :trackers
  fixtures :time_entries
  fixtures :enumerations
  fixtures :issue_statuses
  fixtures :roles
  fixtures :issue_categories
  fixtures :versions

  describe CostQuery::Operator do
    def query(table, field, operator, *values)
      sql = CostQuery::SqlStatement.new table
      yield sql if block_given?
      operator.to_operator.modify sql, field, *values
      ActiveRecord::Base.connection.select_all sql.to_s
    end
    
    def query_on_entries(field, operator, *values)
      sql = CostQuery::SqlStatement.for_entries
      operator.to_operator.modify sql, field, *values
      result = ActiveRecord::Base.connection.select_all sql.to_s
    end

    it "does =" do
      query('projects', 'id', '=', 1).size.should == 1
    end

    it "does = for multiple values" do
      query('projects', 'id', '=', 1, 2).size.should == 2
    end

    it "does <=" do
      query('projects', 'id', '<=', Project.count - 1).size.should == Project.count - 1
    end

    it "does >=" do
      query('projects', 'id', '>=', Project.first.id + 1).size.should == Project.count - 1
    end

    it "does !" do
      query('projects', 'id', '!', 1).size.should == Project.count - 1
    end

    it "does ! for multiple values" do
      query('projects', 'id', '!', 1, 2).size.should == Project.count - 2
    end

    it "does !*" do
      query('cost_entries', 'project_id', '!*', []).size.should == 0
    end

    it "does !~ (not contains)" do
      query('projects', 'id', '!~', 1).size.should == Project.count - 1
    end

    it "does c (closed issue)" do
      query('issues', 'status_id', 'c') { |s| s.join IssueStatus => [Issue, :status] }.size.should >= 0
    end

    it "does o (open issue)" do
      query('issues', 'status_id', 'o') { |s| s.join IssueStatus => [Issue, :status] }.size.should >= 0
    end
    
    it "does give the correct number of results when counting closed and open issues" do
      a = query('issues', 'status_id', 'o') { |s| s.join IssueStatus => [Issue, :status] }.size
      b = query('issues', 'status_id', 'c') { |s| s.join IssueStatus => [Issue, :status] }.size
      Issue.count.should == a + b
    end

    it "does w (this week)" do
      #somehow this test doesn't work on sundays
      n = query('projects', 'created_on', 'w').size
      Project.generate! :created_on => Time.now
      query('projects', 'created_on', 'w').size.should == n + 1
      Project.generate! :created_on => Date.today + 7
      Project.generate! :created_on => Date.today - 7
      query('projects', 'created_on', 'w').size.should == n + 1
    end

    it "does t (today)" do
      s = query('projects', 'created_on', 't').size
      Project.generate! :created_on => Date.yesterday
      query('projects', 'created_on', 't').size.should == s
      Project.generate! :created_on => Time.now
      query('projects', 'created_on', 't').size.should == s + 1
    end

    it "does <t+ (before the day which is n days in the future)" do
      n = query('projects', 'created_on', '<t+', 2).size
      Project.generate! :created_on => Date.tomorrow + 1
      query('projects', 'created_on', '<t+', 2).size.should == n + 1
      Project.generate! :created_on => Date.tomorrow + 2
      query('projects', 'created_on', '<t+', 2).size.should == n + 1
    end

    it "does t+ (n days in the future)" do
      n = query('projects', 'created_on', 't+', 1).size
      Project.generate! :created_on => Date.tomorrow
      query('projects', 'created_on', 't+', 1).size.should == n + 1
      Project.generate! :created_on => Date.tomorrow + 2
      query('projects', 'created_on', 't+', 1).size.should == n + 1
    end

    it "does >t+ (after the day which is n days in the furure)" do
      n = query('projects', 'created_on', '>t+', 1).size
      Project.generate! :created_on => Time.now
      query('projects', 'created_on', '>t+', 1).size.should == n
      Project.generate! :created_on => Date.tomorrow + 1
      query('projects', 'created_on', '>t+', 1).size.should == n + 1
    end

    it "does >t- (after the day which is n days ago)" do
      n = query('projects', 'created_on', '>t-', 1).size
      Project.generate! :created_on => Date.today
      query('projects', 'created_on', '>t-', 1).size.should == n + 1
      Project.generate! :created_on => Date.yesterday - 1
      query('projects', 'created_on', '>t-', 1).size.should == n + 1
    end

    it "does t- (n days ago)" do
      n = query('projects', 'created_on', 't-', 1).size
      Project.generate! :created_on => Date.yesterday
      query('projects', 'created_on', 't-', 1).size.should == n + 1
      Project.generate! :created_on => Date.yesterday - 2
      query('projects', 'created_on', 't-', 1).size.should == n + 1
    end

    it "does <t- (before the day which is n days ago)" do
      n = query('projects', 'created_on', '<t-', 1).size
      Project.generate! :created_on => Date.today
      query('projects', 'created_on', '<t-', 1).size.should == n
      Project.generate! :created_on => Date.yesterday - 1
      query('projects', 'created_on', '<t-', 1).size.should == n + 1
    end

    #Our own operators
    it "does =n" do
      # we have a time_entry with costs==4.2 and a cost_entry with costs==2.3 in our fixtures
      query_on_entries('costs', '=n', 4.2).size.should == Entry.all.select { |e| e.costs == 4.2 }.count
      query_on_entries('costs', '=n', 2.3).size.should == Entry.all.select { |e| e.costs == 2.3 }.count
    end
    
    it "does 0" do
      query_on_entries('costs', '0').size.should == Entry.all.select { |e| e.costs == 0 }.count
    end

    # y/n seem are for filtering overridden costs
    it "does y" do
      query_on_entries('overridden_costs', 'y').size.should == Entry.all.select { |e| e.overridden_costs != nil }.count
    end
    
    it "does n" do
      query_on_entries('overridden_costs', 'n').size.should == Entry.all.select { |e| e.overridden_costs == nil }.count
    end

    it "does =d" do
      #assuming that there aren't more than one project created at the same time (which actually is not true, but works for the first project in our fixtures)
      query('projects', 'created_on', '=d', Project.first.created_on).size.should == 1
    end

    it "does <d" do
      query('projects', 'created_on', '<d', Time.now).size.should == Project.count
    end

    it "does <>d" do
      query('projects', 'created_on', '<>d', Time.now, 5.minutes.from_now).size.should == 0
    end

    it "does >d" do
      #assuming that all projects were created in the past
      query('projects', 'created_on', '>d', Time.now).size.should == 0
    end

  end
end