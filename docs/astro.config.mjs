import { defineConfig } from "astro/config";
import vue from "@astrojs/vue";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  site: "https://lutaml.github.io",
  base: "/lutaml-store",
  integrations: [vue()],
  vite: {
    plugins: [tailwindcss()],
  },
});
