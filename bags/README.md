# Bags

Do not store rosbags in Git. Use host paths such as:

```text
/data/rosbags/YYYY-MM-DD/site/robot/run_id/
```

Containers mount the host bag root at `/bags`.
