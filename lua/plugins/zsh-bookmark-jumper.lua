return {
  {
    url = "https://github.com/jesusmb1995/ohmyzsh-bookmark-jumper",
    lazy = false, -- we want to be able to quicly jump from the get-go
    config = function()
      require('zsh-bookmark-jumper')
    end
  }
}
