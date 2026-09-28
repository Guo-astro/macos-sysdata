import Foundation
import Testing
@testable import SysDataMenu

/// Docker's cost per Compose project, read from the Engine API's disk usage.
struct DockerProjectsTests {
    private static let docker = "/usr/local/bin/docker"

    private static let containers = """
    [
      {"Id": "c-web", "ImageID": "sha256:web", "SizeRw": 5000,
       "Labels": {"com.docker.compose.project": "shop",
                  "com.docker.compose.project.working_dir": "/tmp/sysdata-docker/shop"}},
      {"Id": "c-db", "ImageID": "sha256:postgres", "SizeRw": 100,
       "Labels": {"com.docker.compose.project": "shop",
                  "com.docker.compose.project.working_dir": "/tmp/sysdata-docker/shop"}},
      {"Id": "c-blog-db", "ImageID": "sha256:postgres",
       "Labels": {"com.docker.compose.project": "blog",
                  "com.docker.compose.project.working_dir": "/tmp/sysdata-docker/blog"}},
      {"Id": "c-loose", "ImageID": "sha256:tool", "Labels": {}}
    ]
    """
    private static let images = """
    [
      {"Id": "sha256:web", "RepoTags": ["shop-web:latest", "shop-web:v2"], "Size": 900000000,
       "SharedSize": 200000000, "Created": 1790000000, "Containers": 1},
      {"Id": "sha256:postgres", "RepoTags": ["postgres:16"], "Size": 400000000,
       "SharedSize": 0, "Created": 1700000000, "Containers": 2},
      {"Id": "sha256:tool", "RepoTags": [], "Size": 50000000, "SharedSize": 0, "Containers": 1}
    ]
    """
    private static let volumes = """
    [
      {"Name": "shop_pgdata", "Labels": {"com.docker.compose.project": "shop"},
       "UsageData": {"Size": 300000000, "RefCount": 1}},
      {"Name": "shop_old", "Labels": {"com.docker.compose.project": "shop"},
       "UsageData": {"Size": 700000000, "RefCount": 0}}
    ]
    """

    /// API 1.44 to 1.52: the lists at the top level.
    private static let legacy = """
    {"LayersSize": 1, "Images": \(images), "Containers": \(containers), "Volumes": \(volumes), "BuildCache": []}
    """
    /// API 1.52 and later with `verbose=1`: the lists under each usage.
    private static let current = """
    {"ImagesUsage": {"TotalSize": 1, "Items": \(images)},
     "ContainersUsage": {"TotalSize": 1, "Items": \(containers)},
     "VolumesUsage": {"TotalSize": 1, "Items": \(volumes)},
     "BuildCacheUsage": {"TotalSize": 0}}
    """

    private func items(_ json: String) throws -> [String: StorageItem] {
        let usage = try JSONDecoder().decode(DockerProjects.Usage.self, from: Data(json.utf8))
        let items = DockerProjects.items(from: usage, docker: Self.docker, projectRoot: { $0 })
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    @Test(arguments: [legacy, current])
    func bothResponseShapesAreRead(_ json: String) throws {
        let usage = try JSONDecoder().decode(DockerProjects.Usage.self, from: Data(json.utf8))
        #expect(usage.images.count == 3)
        #expect(usage.containers.count == 4)
        #expect(usage.volumes.count == 2)
    }

    /// The web image is shop's alone and is counted by the part only it
    /// holds. Postgres is run by shop and blog both, so it is neither's: an
    /// archive of one would take it from the other.
    @Test func anImageIsAProjectsOnlyWhenNothingElseRunsIt() throws {
        let items = try items(Self.current)
        let shop = try #require(items["docker-project-images-shop"])
        #expect(shop.sizeBytes == 700_000_000)
        #expect(shop.project?.path == "/tmp/sysdata-docker/shop")
        #expect(shop.partName == "Docker images")
        #expect(shop.builtAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(shop.action.plan == [
            "\(Self.docker) container rm --force c-web c-db",
            "\(Self.docker) image rm shop-web:latest shop-web:v2",
        ])
        #expect(items["docker-project-images-blog"] == nil, "postgres is shared, and blog has nothing else")
    }

    /// A volume in use is the project's data and is only described; one no
    /// container uses is already in the Docker category's prune row, and
    /// counting it here too would count it twice.
    @Test func onlyAttachedVolumesAreListedAndNeverArchived() throws {
        let volumes = try #require(try items(Self.legacy)["docker-project-volumes-shop"])
        #expect(volumes.sizeBytes == 300_000_000)
        #expect(volumes.action.isManual)
    }

    /// Without the shared size, an image's full size would count its base
    /// layers once per image; nothing is claimed instead.
    @Test func anImageWithoutASharedSizeClaimsNothing() {
        let image = DockerProjects.Usage.Image(Id: "x", RepoTags: nil, Size: 900, SharedSize: -1, Created: nil)
        #expect(image.uniqueSize == 0)
    }

    @Test func onlyALocalSocketIsAsked() {
        #expect(DockerProjects.socketPath(fromHost: "unix:///Users/me/.docker/run/docker.sock\n")
                == "/Users/me/.docker/run/docker.sock")
        #expect(DockerProjects.socketPath(fromHost: "tcp://10.0.0.5:2376") == nil)
        #expect(DockerProjects.socketPath(fromHost: "ssh://me@server") == nil)
    }
}
