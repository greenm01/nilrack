import std/unittest

import ../src/embed/wayembed_host

suite "wayembed host":
  test "host interface exposes Wayland handles through C callbacks":
    var compositorMarker: int
    var subcompositorMarker: int
    var shmMarker: int
    var seatMarker: int
    var shellMarker: int
    var host = WayembedHost(
      handles: WayembedHostHandles(
        compositor: addr compositorMarker,
        subcompositor: addr subcompositorMarker,
        shm: addr shmMarker,
        seat: addr seatMarker,
        xdgWmBase: addr shellMarker,
      )
    )

    host.initWayembedHostInterface()

    check host.cInterface.size == uint32(sizeof(WayembedHostInterface))
    check host.cInterface.version == WayembedAbiVersion
    check cast[pointer](host.cInterface.getCompositor(host.cInterface.userdata)) ==
      addr compositorMarker
    check cast[pointer](host.cInterface.getSubcompositor(host.cInterface.userdata)) ==
      addr subcompositorMarker
    check cast[pointer](host.cInterface.getShm(host.cInterface.userdata)) ==
      addr shmMarker
    check cast[pointer](host.cInterface.getSeat(host.cInterface.userdata)) ==
      addr seatMarker
    check cast[pointer](host.cInterface.getXdgWmBase(host.cInterface.userdata)) ==
      addr shellMarker

  test "callbacks update passive lifecycle fields":
    var host: WayembedHost
    host.initWayembedHostInterface()
    var clientMarker: int
    var surfaceMarker: int
    let client = cast[ptr WayembedClient](addr clientMarker)

    host.cInterface.onClientConnected(host.cInterface.userdata, client)
    host.cInterface.onSurfaceCreated(
      host.cInterface.userdata, client, cast[ptr WlSurface](addr surfaceMarker)
    )
    host.cInterface.onEmbedMapped(host.cInterface.userdata, cast[ptr WayembedEmbed](1))
    host.cInterface.onEmbedResized(
      host.cInterface.userdata, cast[ptr WayembedEmbed](1), 320, 200
    )

    check host.client == client
    check host.childSurface == addr surfaceMarker
    check host.mapped
    check host.width == 320
    check host.height == 200

    host.cInterface.onProtocolError(host.cInterface.userdata, client, 7)
    host.cInterface.onClientClosed(host.cInterface.userdata, client)

    check host.failed
    check host.protocolErrorCode == 7
    check host.closed
    check host.client.isNil
