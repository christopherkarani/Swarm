import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Swarm',
  description: 'Multi-agent orchestration for Swift — built for production, not demos.',
  base: '/',

  head: [
    // Satoshi from Fontshare
    ['link', { rel: 'stylesheet', href: 'https://api.fontshare.com/v2/css?f[]=satoshi@300,400,500,600&display=swap' }],
    // Syne + JetBrains Mono from Google Fonts
    ['link', { rel: 'preconnect', href: 'https://fonts.googleapis.com' }],
    ['link', { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' }],
    ['link', { rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=Syne:wght@400;500;600;700;800&family=JetBrains+Mono:ital,wght@0,400;0,500;1,400&display=swap' }],
    // Favicon
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/logo.svg' }],
  ],

  ignoreDeadLinks: false,
  appearance: 'dark',
  lastUpdated: true,
  cleanUrls: true,

  markdown: {
    // Register `svg` as an alias for `xml` so ` ```svg ` fences highlight cleanly
    // instead of falling back to `txt` and emitting build-time warnings.
    languageAlias: {
      svg: 'xml',
    },
  },

  // Exclude internal planning docs, historical reports, and archival generated
  // references that are retained in the repository but are not website docs.
  srcExclude: [
    '**/BEST_PRACTICES.md',
    '**/DSL_IMPLEMENTATION_PROGRESS.md',
    '**/HIVE_V1_*.md',
    '**/SMART_GRAPH_COMPILATION_PLAN.md',
    '**/VOICE_AGENT_IMPLEMENTATION_PLAN.md',
    '**/migration-plan_*.md',
    '**/subagent-context-findings.md',
    '**/MultiProvider.md',
    '**/reference/api-quality-assessment.md',
    '**/reference/docc-audit-report.md',
    '**/reference/docs-folder-audit-report.md',
    '**/reference/documentation-gap-report.md',
    '**/reference/documentation-validation-report.md',
    '**/reference/durable-runtime-hardening.md',
    '**/swarm-features.md',
    '**/swarm-complete-reference.md',
    '**/reference/documentation-improvement-plan.md',
    '**/plans/**',
    '**/superpowers/**',
    '**/validation/**',
    '**/work-packages/**',
  ],

  themeConfig: {
    logo: '/logo.svg',

    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'API Reference', link: '/reference/overview' },
      { text: 'GitHub', link: 'https://github.com/christopherkarani/Swarm' },
    ],

    sidebar: {
      '/guide/': [
        {
          text: 'Introduction',
          items: [
            { text: 'Getting Started', link: '/guide/getting-started' },
            { text: 'Durable Execution', link: '/guide/durable-execution' },
            { text: 'Foundation Models', link: '/guide/foundation-models' },
            { text: 'Remote Providers', link: '/guide/remote-providers' },
            { text: 'Capability Showcase', link: '/guide/capability-showcase' },
            { text: 'Agent Workspace', link: '/guide/agent-workspace' },
            { text: 'OpenTelemetry Tracing', link: '/guide/opentelemetry-tracing' },
            { text: 'Why Swarm', link: '/guide/why-swarm' },
          ]
        },
        {
          text: 'API Reference',
          items: [
            { text: 'Overview', link: '/reference/overview' },
            { text: 'Front-Facing API', link: '/reference/front-facing-api' },
            { text: 'API Catalog', link: '/reference/api-catalog' },
          ]
        },
      ],
      '/reference/': [
        {
          text: 'API Reference',
          items: [
            { text: 'Overview', link: '/reference/overview' },
            { text: 'Front-Facing API', link: '/reference/front-facing-api' },
            { text: 'API Catalog', link: '/reference/api-catalog' },
          ]
        },
      ],
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/christopherkarani/Swarm' },
      { icon: 'x', link: 'https://x.com/ckarani7' },
    ],

    search: {
      provider: 'local',
    },

    editLink: {
      pattern: 'https://github.com/christopherkarani/Swarm/edit/main/docs/:path',
      text: 'Edit this page on GitHub',
    },

    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2025-present Christopher Karani',
    },
  },
})
