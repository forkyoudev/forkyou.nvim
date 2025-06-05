# forkyou.nvim

## Installation

### With `lazy.nvim`

```lua
{
  "yourusername/forkyou.nvim",
  config = function()
    require("forkyou").setup({
      api_token = "YOUR_API_TOKEN", -- Required
    })
  end,
}
```

### Local development

```lua
{
  dir = "~/.config/nvim/lua/forkyou",
  config = function()
    require("forkyou").setup({
      api_token = "YOUR_API_TOKEN",
    })
  end,
}
```

## Dependencies

Install the following dependencies with `luarocks`:

```bash
luarocks install luaossl    # Required for HMAC signature
luarocks install dkjson     # Required for JSON encoding
```

## API Token

1. Go to [forkyou.dev](https://forkyou.dev)
2. Copy your API token from the dashboard
3. Paste it in your plugin setup:

```lua
require("forkyou").setup({
  api_token = "paste-your-token-here",
})
```
