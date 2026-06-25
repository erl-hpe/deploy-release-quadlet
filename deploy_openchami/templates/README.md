# OpenCHAMI Deployment Tool File Templates

These files provide the templates referred to by the `manifest'
section of the configuration. Some of them are scripts used directly
by the deployment tool and some of them are supporting or system data
files created by the deployment tool. Look in the `manifest` section of
the config to see where they each get created. To generate the final
files from them without running a full deployment, use

```
deploy_openchami -f
```

The generated results can then be examined in situ.

__NOTE: many of these files are system configuration files. While the
  templates are copyrighted and made available under the MIT license,
  it would be inappropriate to copyright the resulting
  configuration. In these cases, even for file formats that support
  comments, a companion `.license` file has been provided that covers
  the template.__
