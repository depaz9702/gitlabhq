# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :appearance do
    title       "MepMep"
    description "This is my Community Edition instance"
    new_project_guidelines "Custom project guidelines"
  end
end
