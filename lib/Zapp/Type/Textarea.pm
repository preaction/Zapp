package Zapp::Type::Textarea;
use Mojo::Base 'Zapp::Type::Text', -signatures;

1;
__DATA__
@@ input.html.ep
%= include 'zapp/textarea', name => 'value', value => $value // $config

@@ config.html.ep
<label for="config">Value</label>
%= include 'zapp/textarea', name => 'config', value => $config

@@ output.html.ep
<div class="text-break text-pre-wrap">
    %= $value
</div>

