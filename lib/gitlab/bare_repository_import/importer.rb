module Gitlab
  module BareRepositoryImport
    class Importer
      NoAdminError = Class.new(StandardError)

      def self.execute(import_path)
        import_path << '/' unless import_path.ends_with?('/')
        repos_to_import = Dir.glob(import_path + '**/*.git')

        unless user = User.admins.order_id_asc.first
          raise NoAdminError.new('No admin user found to import repositories')
        end

        repos_to_import.each do |repo_path|
          bare_repo = Gitlab::BareRepositoryImport::Repository.new(import_path, repo_path)

          if bare_repo.hashed? || bare_repo.wiki?
            log " * Skipping repo #{bare_repo.repo_path}".color(:yellow)

            next
          end

          log "Processing #{repo_path}".color(:yellow)

          new(user, bare_repo).create_project_if_needed
        end
      end

      attr_reader :user, :project_name, :bare_repo

      delegate :log, to: :class
      delegate :project_name, :project_full_path, :group_path, :repo_path, :wiki_path, to: :bare_repo

      def initialize(user, bare_repo)
        @user = user
        @bare_repo = bare_repo
      end

      def create_project_if_needed
        if project = Project.find_by_full_path(project_full_path)
          log " * #{project.name} (#{project_full_path}) exists"

          return project
        end

        create_project
      end

      private

      def create_project
        group = find_or_create_groups

        project = Projects::CreateService.new(user,
                                              name: project_name,
                                              path: project_name,
                                              skip_disk_validation: true,
                                              import_type: 'gitlab_project',
                                              namespace_id: group&.id).execute

        if project.persisted? && mv_repo(project)
          log " * Created #{project.name} (#{project_full_path})".color(:green)

          ProjectCacheWorker.perform_async(project.id)
        else
          log " * Failed trying to create #{project.name} (#{project_full_path})".color(:red)
          log "   Errors: #{project.errors.messages}".color(:red) if project.errors.any?
        end

        project
      end

      def mv_repo(project)
        FileUtils.mv(repo_path, File.join(project.repository_storage_path, project.disk_path + '.git'))

        if bare_repo.wiki_exists?
          FileUtils.mv(wiki_path, File.join(project.repository_storage_path, project.disk_path + '.wiki.git'))
        end

        true
      rescue => e
        log " * Failed to move repo: #{e.message}".color(:red)

        false
      end

      def find_or_create_groups
        return nil unless group_path.present?

        log " * Using namespace: #{group_path}"

        Groups::NestedCreateService.new(user, group_path: group_path).execute
      end

      # This is called from within a rake task only used by Admins, so allow writing
      # to STDOUT
      def self.log(message)
        puts message # rubocop:disable Rails/Output
      end
    end
  end
end
