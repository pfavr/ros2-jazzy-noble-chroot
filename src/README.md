# ROS workspace source

Put project ROS 2 packages in this directory. Development containers mount the
repository at `/workspaces/robot`; release image targets copy this directory into
the builder stage and build it with colcon.
