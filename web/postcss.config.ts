import type { Config } from "postcss"

const config: Config = {
    plugins: {
        "@tailwindcss/postcss": {},
        autoprefixer: {},
    },
}

export default config
