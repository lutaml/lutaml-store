import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Lutaml::Store',
  description: 'Store-centric database-style API for Lutaml::Model objects',
  lang: 'en-US',
  lastUpdated: true,
  head: [
    ['link', { rel: 'preconnect', href: 'https://fonts.googleapis.com' }],
    ['link', { rel: 'preconnect', href: 'https://fonts.gstatic.com' }, ],
    ['link', { href: 'https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700&display=swap', rel: 'stylesheet' }],
    ['meta', { name: 'theme-color', content: '#1e40af' }],
  ],
  themeConfig: {
    siteTitle: 'Lutaml::Store',
    socialLinks: [
      { icon: 'github', link: 'https://github.com/lutaml/lutaml-store' }
    ],
    sidebar: [
      {
        text: 'Getting Started',
        items: [
          { text: 'Introduction', link: '/' },
          { text: 'Quick Start', link: '/quick-start' },
        ],
      },
      {
        text: 'Architecture',
        items: [
          { text: 'Sources', link: '/sources' },
          { text: 'Cloud Store Contract', link: '/cloud-contract' },
        ],
      },
    ],
  },
})
